//! Decoding voice messages to what Whisper wants: 16 kHz mono f32 PCM.
//!
//! Containers and most codecs come from Symphonia (pure Rust). Symphonia has
//! no Opus decoder, and Opus is what nearly every voice message uses (Ogg/Opus
//! from Element, FluffyChat and us; WebM/Opus from some web recorders), so
//! Opus packets go to libopus instead, which decodes straight to 16 kHz mono.

use std::io::Cursor;

use anyhow::{anyhow, bail, Context, Result};
use symphonia::core::codecs::audio::well_known::CODEC_ID_OPUS;
use symphonia::core::codecs::audio::{AudioCodecParameters, AudioDecoderOptions};
use symphonia::core::codecs::CodecParameters;
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, FormatReader, TrackType};
use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::MetadataOptions;

/// Sample rate Whisper models expect.
pub const WHISPER_RATE: u32 = 16_000;

/// Decodes a whole audio file (any container/codec we support) to 16 kHz mono.
/// [mime_type] is only a hint for the probe; the content decides.
pub fn decode_to_whisper_pcm(bytes: Vec<u8>, mime_type: Option<&str>) -> Result<Vec<f32>> {
    let mut hint = Hint::new();
    if let Some(mime) = mime_type {
        hint.mime_type(mime);
    }
    let mss = MediaSourceStream::new(
        Box::new(Cursor::new(bytes)),
        MediaSourceStreamOptions::default(),
    );
    let mut format = symphonia::default::get_probe()
        .probe(
            &hint,
            mss,
            FormatOptions::default(),
            MetadataOptions::default(),
        )
        .context("unrecognised audio format")?;

    let track = format
        .first_track(TrackType::Audio)
        .ok_or_else(|| anyhow!("no audio track"))?;
    let track_id = track.id;
    let params = match &track.codec_params {
        Some(CodecParameters::Audio(p)) => p.clone(),
        _ => bail!("audio track has no codec parameters"),
    };

    if params.codec == CODEC_ID_OPUS {
        decode_opus(format.as_mut(), track_id, &params)
    } else {
        decode_symphonia(format.as_mut(), track_id, &params)
    }
}

fn decode_opus(
    format: &mut dyn FormatReader,
    track_id: u32,
    params: &AudioCodecParameters,
) -> Result<Vec<f32>> {
    // libopus downmixes any stream to the channel count asked for here.
    let mut decoder = opus::Decoder::new(WHISPER_RATE, opus::Channels::Mono)
        .map_err(|e| anyhow!("opus decoder: {e}"))?;
    // OpusHead pre-skip is counted at 48 kHz.
    let mut skip = params
        .extra_data
        .as_deref()
        .filter(|head| head.len() >= 12 && head.starts_with(b"OpusHead"))
        .map(|head| u16::from_le_bytes([head[10], head[11]]) as usize / 3)
        .unwrap_or(0);

    // 120 ms is the longest Opus packet.
    let mut frame = vec![0f32; WHISPER_RATE as usize * 120 / 1000];
    let mut out = Vec::new();
    while let Some(packet) = next_packet(format)? {
        if packet.track_id != track_id || packet.data.is_empty() {
            continue;
        }
        // A corrupt packet loses 20 ms or so; keep going.
        let Ok(n) = decoder.decode_float(&packet.data, &mut frame, false) else {
            continue;
        };
        let drop = skip.min(n);
        skip -= drop;
        out.extend_from_slice(&frame[drop..n]);
    }
    Ok(out)
}

fn decode_symphonia(
    format: &mut dyn FormatReader,
    track_id: u32,
    params: &AudioCodecParameters,
) -> Result<Vec<f32>> {
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(params, &AudioDecoderOptions::default())
        .context("unsupported audio codec")?;

    let mut rate = params.sample_rate.unwrap_or(0);
    let mut mono = Vec::new();
    let mut interleaved: Vec<f32> = Vec::new();
    while let Some(packet) = next_packet(format)? {
        if packet.track_id != track_id {
            continue;
        }
        let buf = match decoder.decode(&packet) {
            Ok(buf) => buf,
            Err(SymphoniaError::DecodeError(_)) => continue,
            Err(e) => return Err(e.into()),
        };
        let channels = buf.spec().channels().count().max(1);
        rate = buf.spec().rate();
        interleaved.clear();
        buf.copy_to_vec_interleaved(&mut interleaved);
        mono.extend(
            interleaved
                .chunks_exact(channels)
                .map(|frame| frame.iter().sum::<f32>() / channels as f32),
        );
    }
    if rate == 0 {
        bail!("unknown sample rate");
    }
    Ok(resample(&mono, rate, WHISPER_RATE))
}

/// Next packet, or None at the end of the stream (Symphonia reports a
/// truncated last page as an unexpected EOF).
fn next_packet(format: &mut dyn FormatReader) -> Result<Option<symphonia::core::packet::Packet>> {
    match format.next_packet() {
        Ok(p) => Ok(p),
        Err(SymphoniaError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
            Ok(None)
        }
        Err(e) => Err(e.into()),
    }
}

/// Windowed-sinc resampler. Plenty for speech, and a 30 s clip takes a few
/// milliseconds.
pub fn resample(input: &[f32], from: u32, to: u32) -> Vec<f32> {
    if from == to || input.is_empty() {
        return input.to_vec();
    }
    const HALF_TAPS: isize = 16;
    let step = from as f64 / to as f64;
    // Low-pass at the lower Nyquist so downsampling doesn't alias.
    let cutoff = (to as f64 / from as f64).min(1.0) * 0.95;
    let out_len = ((input.len() as f64) / step).floor() as usize;
    let mut out = Vec::with_capacity(out_len);
    for i in 0..out_len {
        let center = i as f64 * step;
        let base = center.floor() as isize;
        let mut acc = 0.0;
        let mut norm = 0.0;
        for k in (base - HALF_TAPS + 1)..=(base + HALF_TAPS) {
            if k < 0 || k as usize >= input.len() {
                continue;
            }
            let x = k as f64 - center;
            let w = sinc(x * cutoff) * blackman(x / HALF_TAPS as f64);
            acc += input[k as usize] as f64 * w;
            norm += w;
        }
        out.push(if norm.abs() > 1e-9 {
            (acc / norm) as f32
        } else {
            0.0
        });
    }
    out
}

fn sinc(x: f64) -> f64 {
    if x.abs() < 1e-9 {
        1.0
    } else {
        let px = std::f64::consts::PI * x;
        px.sin() / px
    }
}

/// Blackman window over -1..1.
fn blackman(t: f64) -> f64 {
    if t.abs() >= 1.0 {
        return 0.0;
    }
    let a = std::f64::consts::PI * (t + 1.0);
    0.42 - 0.5 * a.cos() + 0.08 * (2.0 * a).cos()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(freq: f64, rate: u32, secs: f64) -> Vec<f32> {
        (0..(rate as f64 * secs) as usize)
            .map(|i| {
                (2.0 * std::f64::consts::PI * freq * i as f64 / rate as f64).sin() as f32 * 0.5
            })
            .collect()
    }

    fn rms(x: &[f32]) -> f64 {
        (x.iter().map(|v| (*v as f64).powi(2)).sum::<f64>() / x.len() as f64).sqrt()
    }

    fn wav(samples: &[f32], rate: u32, channels: u16) -> Vec<u8> {
        let data: Vec<u8> = samples
            .iter()
            .flat_map(|s| {
                let v = (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                std::iter::repeat_n(v, channels as usize).flat_map(|v| v.to_le_bytes())
            })
            .collect();
        let mut out = Vec::new();
        out.extend_from_slice(b"RIFF");
        out.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
        out.extend_from_slice(b"WAVEfmt ");
        out.extend_from_slice(&16u32.to_le_bytes());
        out.extend_from_slice(&1u16.to_le_bytes());
        out.extend_from_slice(&channels.to_le_bytes());
        out.extend_from_slice(&rate.to_le_bytes());
        out.extend_from_slice(&(rate * channels as u32 * 2).to_le_bytes());
        out.extend_from_slice(&(channels * 2).to_le_bytes());
        out.extend_from_slice(&16u16.to_le_bytes());
        out.extend_from_slice(b"data");
        out.extend_from_slice(&(data.len() as u32).to_le_bytes());
        out.extend_from_slice(&data);
        out
    }

    #[test]
    fn resample_keeps_length_and_passband() {
        let input = sine(440.0, 48_000, 1.0);
        let out = resample(&input, 48_000, 16_000);
        assert_eq!(out.len(), 16_000);
        let ratio = rms(&out[100..out.len() - 100]) / rms(&input);
        assert!((ratio - 1.0).abs() < 0.05, "passband gain {ratio}");
    }

    #[test]
    fn resample_filters_above_nyquist() {
        // 12 kHz can't exist at 16 kHz; it must not fold back into speech.
        let input = sine(12_000.0, 48_000, 1.0);
        let out = resample(&input, 48_000, 16_000);
        let ratio = rms(&out[100..out.len() - 100]) / rms(&input);
        assert!(ratio < 0.05, "alias leak {ratio}");
    }

    #[test]
    fn decodes_stereo_wav_to_16k_mono() {
        let input = sine(300.0, 44_100, 0.5);
        let out = decode_to_whisper_pcm(wav(&input, 44_100, 2), Some("audio/wav")).unwrap();
        assert!((out.len() as i64 - 8_000).abs() <= 2, "len {}", out.len());
        let ratio = rms(&out[100..out.len() - 100]) / rms(&input);
        assert!((ratio - 1.0).abs() < 0.05, "gain {ratio}");
    }

    #[test]
    fn rejects_garbage() {
        assert!(decode_to_whisper_pcm(vec![7u8; 1000], None).is_err());
    }
}

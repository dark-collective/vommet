# Vommet CI image: the runner's default job image plus everything the build,
# android, flatpak-bundle and integration workflows used to install on every
# run. Rebuild when FLUTTER_VERSION / TUWUNEL_VERSION / the apt list changes;
# tag = flutter version + date.
FROM ghcr.io/catthehacker/ubuntu:act-22.04

ARG FLUTTER_VERSION=3.41.9
ARG TUWUNEL_VERSION=v1.9.3
ARG CMDLINE_TOOLS_ZIP=commandlinetools-linux-11076708_latest.zip
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils git unzip zip build-essential clang lld llvm cmake ninja-build pkg-config \
      libgtk-3-dev libmpv-dev mpv ffmpeg libmimalloc-dev libwebkit2gtk-4.1-dev \
      libasound2-dev libkeybinder-3.0-dev libglu1-mesa libstdc++-12-dev libsecret-1-dev libjsoncpp-dev \
      xvfb jq openssl zstd dbus dbus-x11 gnome-keyring dunst \
      openjdk-17-jdk-headless \
 && rm -rf /var/lib/apt/lists/*

# Flutter (precached for Linux + Android) and Rust (+ Android target).
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" | tar -xJ -C /root \
 && git config --global --add safe.directory '*' \
 && /root/flutter/bin/flutter config --no-analytics --enable-linux-desktop \
 && /root/flutter/bin/flutter precache --linux --android \
 && curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal \
 && /root/.cargo/bin/rustup target add aarch64-linux-android

# Android SDK: command-line tools, licences, platform-tools (Gradle fetches the rest).
ENV ANDROID_HOME=/root/android-sdk ANDROID_SDK_ROOT=/root/android-sdk
RUN mkdir -p $ANDROID_HOME/cmdline-tools && cd /tmp \
 && curl -fsSL -o tools.zip "https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}" \
 && unzip -q tools.zip && mv cmdline-tools $ANDROID_HOME/cmdline-tools/latest && rm tools.zip \
 && (yes || true) | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null \
 && $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platform-tools" >/dev/null

# Integration tests' homeserver.
RUN curl -fsSL "https://github.com/matrix-construct/tuwunel/releases/download/${TUWUNEL_VERSION}/${TUWUNEL_VERSION}-release-all-x86_64-v1-linux-gnu-tuwunel.zst" \
      | zstd -d -o /root/tuwunel-${TUWUNEL_VERSION} && chmod +x /root/tuwunel-${TUWUNEL_VERSION}

ENV PATH=/root/flutter/bin:/root/.cargo/bin:$PATH
LABEL org.opencontainers.image.source="https://nether.codes/nether/vommet"

# PulseAudio headers: the fork's flutter_webrtc (Linux app-audio capture for
# screen share, #4) requires them at build time.
RUN apt-get update && apt-get install -y --no-install-recommends libpulse-dev \
 && rm -rf /var/lib/apt/lists/*

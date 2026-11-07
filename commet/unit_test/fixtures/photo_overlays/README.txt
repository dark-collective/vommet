Tiny synthetic testsrc/color fixtures generated with FFmpeg for Vommet issue 1056.
animated.png: ffmpeg -f lavfi -i testsrc=size=8x8:rate=2:duration=1 -plays 0 animated.apng
animated.webp: same testsrc, -loop 0 animated.webp
still.webp: ffmpeg -f lavfi -i color=blue:size=8x8 -frames:v 1 still.webp

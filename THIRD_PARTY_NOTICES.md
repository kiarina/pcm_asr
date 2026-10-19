# Third-party notices

## whisper.cpp and ggml (Windows backend)

The Windows backend compiles [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
v1.9.5 and its bundled ggml into `pcm_asr_whisper.dll`. Both are licensed
under the MIT License:

```
MIT License

Copyright (c) 2023-2024 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The source is not vendored; `tool/fetch_whisper_cpp.sh` / `.ps1` download the
release archive and verify its SHA-256.

## Whisper models

`prepare()` downloads ggml conversions of OpenAI's Whisper models from
https://huggingface.co/ggerganov/whisper.cpp (MIT, see that repository). The
original Whisper weights are released by OpenAI under the MIT License.

## Derived code

`src/pcm_asr_whisper.c` and `lib/src/windows/whisper_engine.dart` derive from
the `whisper_cpp` package of the `kiarina/labs` repository
(`2026/10/18/flutter-realtime-audio-analysis`, MIT).

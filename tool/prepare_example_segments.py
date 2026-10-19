"""Cut the shared two-speaker conversation (kiarina/test-assets, mp3) into the
six finalized segments the example app plays: example/assets/segments/
(git-ignored). Pass the path to conversation_2speaker_14s_16k.mp3.

  python3 tool/prepare_example_segments.py ~/src/github.com/kiarina/labs/tests/assets/mp3/conversation_2speaker_14s_16k.mp3
"""
import hashlib
import json
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
assets = root / 'example/assets/segments'
assets.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    wav_path = Path(tmp) / 'source.wav'
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(source), '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', str(wav_path)], check=True)
    with wave.open(str(wav_path)) as w:
        pcm = w.readframes(w.getnframes())
assert hashlib.sha256(pcm).hexdigest() == 'aef288721e2f461c844ef766264cbcf09d997baf34fd72872faaebf0618dd06e'
refs = json.loads((root / 'example/fixtures/scd.json').read_text())
texts = (root / 'example/fixtures/reference.txt').read_text().splitlines()
rows = []
for i, (r, text) in enumerate(zip(refs, texts)):
    a, b = round(r['start'] * 16000), round(r['end'] * 16000)
    raw = pcm[a * 2:b * 2]
    name = f'segment-{i + 1}.pcm'
    (assets / name).write_bytes(raw)
    rows.append({'id': f'segment-{i + 1}', 'speaker_id': f'speaker-{r["speaker"] + 1}', 'start': a / 16000, 'end': b / 16000, 'file': name,
                 'sample_rate': 16000, 'channels': 1, 'reference': text, 'samples': b - a, 'pcm_sha256': hashlib.sha256(raw).hexdigest()})
(assets / 'segments.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
print(f'{len(rows)} segments written to {assets.relative_to(root)}')

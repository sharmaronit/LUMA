"""Original soft BRAVIA-inspired chimes; no sampled Sony or video audio."""
import math
from pathlib import Path
import struct
import wave

OUTPUT = Path(__file__).resolve().parents[1] / "android/app/src/main/res/raw"
RATE = 48000


def chime(name, duration, notes, peak):
    frames = bytearray()
    count = round(RATE * duration)
    for index in range(count):
        t = index / RATE
        progress = index / (count - 1)
        sample = 0.0
        for frequency, gain, onset in notes:
            elapsed = t - onset
            if elapsed < 0:
                continue
            # A soft mallet attack, faint bell partial and two quiet reflections.
            # No noise impulse or abrupt cutoff, even during repeated navigation.
            for delay, reflection in [(0, 1), (.027, .10), (.053, .045)]:
                local = elapsed - delay
                if local < 0:
                    continue
                attack = math.sin(min(1, local / .022) * math.pi / 2) ** 2
                decay = math.exp(-local * 10)
                tone = (math.sin(2 * math.pi * frequency * local)
                        + .065 * math.sin(2 * math.pi * frequency * 2.003 * local)
                        * math.exp(-local * 15))
                sample += tone * attack * decay * gain * reflection
        sample *= peak * (1 - progress) ** 2 / sum(g for _, g, _ in notes)
        frames.extend(struct.pack('<h', round(sample * 32767)))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT / f'luma_{name}.wav'), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(frames)


if __name__ == '__main__':
    chime('move', .30, [(880, 1, 0)], .085)
    chime('select', .40, [(880, 1, 0), (1318.51, .38, .045)], .105)
    chime('back', .34, [(659.25, 1, 0)], .075)

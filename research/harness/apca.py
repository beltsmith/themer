# APCA-W3 0.0.98G-4g (constants from github.com/Myndex/apca-w3)
def _y(hex_):
    h = hex_.lstrip('#'); r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    return 0.2126729 * r**2.4 + 0.7151522 * g**2.4 + 0.0721750 * b**2.4

def apca_lc(text, bg):
    t, b = _y(text), _y(bg)
    t = t if t > 0.022 else t + (0.022 - t) ** 1.414
    b = b if b > 0.022 else b + (0.022 - b) ** 1.414
    if abs(b - t) < 0.0005: return 0.0
    if b > t:   # normal polarity: dark text on light bg
        s = (b**0.56 - t**0.57) * 1.14
        return 0.0 if s < 0.1 else (s - 0.027) * 100
    s = (b**0.65 - t**0.62) * 1.14  # reverse: light text on dark bg
    return 0.0 if s > -0.1 else (s + 0.027) * 100

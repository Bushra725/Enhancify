"""Authors the aesthetic sticker pack as SVG and renders transparent PNGs
with headless Chromium. Output: assets/stickers/<category>/<name>.png plus a
Dart catalog lib/data/sticker_data.dart."""
import math, os, sys, json
from playwright.sync_api import sync_playwright

APP = sys.argv[1]
FONTS = os.path.join(APP, 'assets/fonts')
OUT = os.path.join(APP, 'assets/stickers')

PINK = '#EA026A'; BLUSH = '#FFC2DA'; SOFT = '#FF8DBB'; CREAM = '#FFF6EA'
GOLD = '#F6B94A'; SAGE = '#9DB89A'; LAV = '#C7A8F0'; SKY = '#A9D6F5'
BROWN = '#8A5A3C'; INK = '#3B2230'

def heart_path(cx=100, cy=100, s=1.0):
    p = [(0, 70), (-60, 25), (-85, -10), (-65, -45), (-45, -78), (-10, -70), (0, -42),
         (10, -70), (45, -78), (65, -45), (85, -10), (60, 25), (0, 70)]
    P = lambda i: f"{cx + p[i][0]*s:.1f} {cy + p[i][1]*s:.1f}"
    return (f"M{P(0)} C{P(1)} {P(2)} {P(3)} C{P(4)} {P(5)} {P(6)} "
            f"C{P(7)} {P(8)} {P(9)} C{P(10)} {P(11)} {P(12)} Z")

def sparkle(cx, cy, r, fill, k=0.18):
    a = r * k
    return (f'<path d="M{cx} {cy-r} C{cx+a} {cy-a} {cx+a} {cy-a} {cx+r} {cy} '
            f'C{cx+a} {cy+a} {cx+a} {cy+a} {cx} {cy+r} C{cx-a} {cy+a} {cx-a} {cy+a} {cx-r} {cy} '
            f'C{cx-a} {cy-a} {cx-a} {cy-a} {cx} {cy-r} Z" fill="{fill}"/>')

def star5(cx, cy, R, r, fill, stroke='none', sw=0):
    pts = []
    for i in range(10):
        ang = -math.pi/2 + i*math.pi/5
        rad = R if i % 2 == 0 else r
        pts.append(f"{cx+rad*math.cos(ang):.1f},{cy+rad*math.sin(ang):.1f}")
    return f'<polygon points="{" ".join(pts)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round"/>'

def flower(cx, cy, n, pr, pw, dist, fill, center, cr, rot=0, stroke='none'):
    s = ''
    for i in range(n):
        a = rot + 360*i/n
        s += (f'<ellipse cx="{cx}" cy="{cy-dist}" rx="{pw}" ry="{pr}" fill="{fill}" stroke="{stroke}" '
              f'stroke-width="2" transform="rotate({a} {cx} {cy})"/>')
    s += f'<circle cx="{cx}" cy="{cy}" r="{cr}" fill="{center}"/>'
    return s

def bow(fill, knot, shade):
    return f'''
    <path d="M100 96 C72 50 22 52 28 96 C34 138 76 124 100 106 Z" fill="{fill}"/>
    <path d="M100 96 C128 50 178 52 172 96 C166 138 124 124 100 106 Z" fill="{fill}"/>
    <path d="M60 84 C74 80 86 88 96 98" stroke="{shade}" stroke-width="4" fill="none" stroke-linecap="round"/>
    <path d="M140 84 C126 80 114 88 104 98" stroke="{shade}" stroke-width="4" fill="none" stroke-linecap="round"/>
    <path d="M94 106 L66 172 L84 164 L94 180 L104 110 Z" fill="{fill}"/>
    <path d="M106 106 L134 172 L116 164 L106 180 L96 110 Z" fill="{fill}"/>
    <rect x="86" y="86" width="28" height="30" rx="10" fill="{knot}"/>'''

def butterfly(w1, w2, body):
    return f'''
    <ellipse cx="68" cy="78" rx="40" ry="48" fill="{w1}" transform="rotate(-25 68 78)"/>
    <ellipse cx="132" cy="78" rx="40" ry="48" fill="{w1}" transform="rotate(25 132 78)"/>
    <ellipse cx="74" cy="135" rx="28" ry="32" fill="{w2}" transform="rotate(20 74 135)"/>
    <ellipse cx="126" cy="135" rx="28" ry="32" fill="{w2}" transform="rotate(-20 126 135)"/>
    <circle cx="66" cy="74" r="10" fill="#fff" opacity=".55"/><circle cx="134" cy="74" r="10" fill="#fff" opacity=".55"/>
    <rect x="94" y="52" width="12" height="104" rx="6" fill="{body}"/>
    <path d="M98 54 C92 36 82 28 74 26" stroke="{body}" stroke-width="3" fill="none" stroke-linecap="round"/>
    <path d="M102 54 C108 36 118 28 126 26" stroke="{body}" stroke-width="3" fill="none" stroke-linecap="round"/>'''

def tape(color, pattern):
    jag = 'M22 70 L30 76 L22 82 L30 88 L22 94 L30 100 L22 106 L30 112 L22 118 L30 124 L22 130 ' \
          'L178 130 L170 124 L178 118 L170 112 L178 106 L170 100 L178 94 L170 88 L178 82 L170 76 L178 70 Z'
    return f'''<defs><clipPath id="t"><path d="{jag}"/></clipPath></defs>
    <g transform="rotate(-8 100 100)"><path d="{jag}" fill="{color}" opacity=".88"/>
    <g clip-path="url(#t)" opacity=".55">{pattern}</g></g>'''

def stripes(c):
    return ''.join(f'<rect x="{x}" y="60" width="8" height="80" fill="{c}" transform="skewX(-20)"/>' for x in range(0, 260, 20))

def dots(c):
    return ''.join(f'<circle cx="{x}" cy="{y}" r="4" fill="{c}"/>' for x in range(30, 180, 16) for y in range(76, 130, 16))

def grid(c):
    return (''.join(f'<rect x="{x}" y="60" width="2" height="80" fill="{c}"/>' for x in range(24, 180, 12)) +
            ''.join(f'<rect x="20" y="{y}" width="160" height="2" fill="{c}"/>' for y in range(72, 132, 12)))

def word(text, font, size, fill, stroke='#fff', sw=10, rot=0, y=112, ls=0):
    return (f'<text x="100" y="{y}" text-anchor="middle" font-family="{font}" font-size="{size}" '
            f'letter-spacing="{ls}" transform="rotate({rot} 100 100)" '
            f'stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" paint-order="stroke" fill="{fill}">{text}</text>')

S = {}  # (category, name) -> (svg inner, diecut)

def add(cat, name, svg, diecut=False):
    S[(cat, name)] = (svg, diecut)

# ---------------------------------------------------------------- Cute
add('Cute', 'bow_pink', bow('#FF8DBB', '#EA026A', '#D6005F'), True)
add('Cute', 'bow_white', bow('#FFFFFF', '#F3E6EC', '#E7C9D6'))
add('Cute', 'bow_red', bow('#E0354F', '#B8193A', '#A5122F'), True)
add('Cute', 'bow_lilac', bow('#C7A8F0', '#9E78D8', '#8E68C8'), True)
add('Cute', 'bow_cream', bow('#F7E3C8', '#E6C79E', '#D9B585'), True)
add('Cute', 'butterfly_pink', butterfly('#FF9CC5', '#FFC6DC', INK), True)
add('Cute', 'butterfly_blue', butterfly('#8EC5F0', '#C4E3FA', INK), True)
add('Cute', 'butterfly_lilac', butterfly('#C7A8F0', '#E4D3FA', INK), True)
add('Cute', 'sparkle_gold', sparkle(100, 100, 80, GOLD) + sparkle(160, 45, 22, '#FFD98A') + sparkle(45, 160, 16, '#FFD98A'))
add('Cute', 'sparkle_pink', sparkle(100, 100, 80, SOFT) + sparkle(155, 50, 20, BLUSH))
add('Cute', 'sparkle_white', sparkle(90, 105, 70, '#FFFFFF') + sparkle(150, 45, 26, '#FFFFFF') + sparkle(160, 150, 14, '#FFFFFF'))
add('Cute', 'star_gold', star5(100, 102, 80, 36, '#FFCB5C', '#F0A92E', 6), True)
add('Cute', 'stars_twinkle', star5(70, 80, 40, 18, GOLD) + star5(140, 70, 26, 12, SOFT) + star5(125, 140, 32, 14, LAV))
add('Cute', 'moon', '<path d="M125 30 A72 72 0 1 0 170 140 A58 58 0 1 1 125 30 Z" fill="#FFD98A"/>' + sparkle(150, 70, 16, '#FFE7B0'), True)
add('Cute', 'cloud', '<path d="M50 140 C22 140 22 100 50 98 C48 66 92 56 104 80 C114 56 160 60 156 96 C184 96 184 140 156 140 Z" fill="#FFFFFF" stroke="#D9E6F2" stroke-width="4"/>', True)
add('Cute', 'rainbow', ''.join(f'<path d="M{30+i*12} 150 A{70-i*12} {70-i*12} 0 0 1 {170-i*12} 150" stroke="{c}" stroke-width="12" fill="none"/>'
                                for i, c in enumerate(['#FF8FAB', '#FFC48C', '#FFE38C', '#A8E6B8', '#9CCBF5']))
    + '<ellipse cx="38" cy="152" rx="24" ry="14" fill="#fff"/><ellipse cx="162" cy="152" rx="24" ry="14" fill="#fff"/>', True)
add('Cute', 'sun', ''.join(f'<rect x="96" y="14" width="8" height="28" rx="4" fill="#FFC04D" transform="rotate({a} 100 100)"/>' for a in range(0, 360, 30))
    + '<circle cx="100" cy="100" r="50" fill="#FFD25C"/><circle cx="84" cy="94" r="5" fill="' + INK + '"/><circle cx="116" cy="94" r="5" fill="' + INK + '"/>'
    + '<path d="M84 112 Q100 126 116 112" stroke="' + INK + '" stroke-width="4" fill="none" stroke-linecap="round"/>'
    + '<circle cx="74" cy="110" r="7" fill="#FF9CB5" opacity=".7"/><circle cx="126" cy="110" r="7" fill="#FF9CB5" opacity=".7"/>', True)
add('Cute', 'crown', '<path d="M34 140 L26 62 L66 96 L100 48 L134 96 L174 62 L166 140 Z" fill="#FFCB5C" stroke="#E8A42A" stroke-width="5" stroke-linejoin="round"/>'
    '<rect x="34" y="138" width="132" height="20" rx="6" fill="#F4B63F"/><circle cx="100" cy="112" r="10" fill="#EA026A"/><circle cx="62" cy="118" r="7" fill="#8EC5F0"/><circle cx="138" cy="118" r="7" fill="#8EC5F0"/>', True)
add('Cute', 'cat', '<path d="M40 70 L52 26 L84 56 Q100 52 116 56 L148 26 L160 70 Q172 100 160 128 Q140 166 100 166 Q60 166 40 128 Q28 100 40 70 Z" fill="#FFF3E6" stroke="' + INK + '" stroke-width="5"/>'
    '<path d="M56 42 L60 62 L74 56 Z M144 42 L140 62 L126 56 Z" fill="#FFB3CC"/><circle cx="78" cy="104" r="7" fill="' + INK + '"/><circle cx="122" cy="104" r="7" fill="' + INK + '"/>'
    '<path d="M94 118 L106 118 L100 125 Z" fill="#FF8DBB"/><path d="M100 125 Q92 134 84 128 M100 125 Q108 134 116 128" stroke="' + INK + '" stroke-width="3.5" fill="none" stroke-linecap="round"/>'
    '<circle cx="64" cy="122" r="8" fill="#FFB3CC" opacity=".8"/><circle cx="136" cy="122" r="8" fill="#FFB3CC" opacity=".8"/>', True)
add('Cute', 'teddy', '<circle cx="54" cy="56" r="26" fill="#C8906A"/><circle cx="146" cy="56" r="26" fill="#C8906A"/><circle cx="54" cy="56" r="13" fill="#E8B892"/><circle cx="146" cy="56" r="13" fill="#E8B892"/>'
    '<circle cx="100" cy="106" r="66" fill="#C8906A"/><ellipse cx="100" cy="128" rx="30" ry="24" fill="#EFCFB1"/><circle cx="76" cy="96" r="7" fill="' + INK + '"/><circle cx="124" cy="96" r="7" fill="' + INK + '"/>'
    '<ellipse cx="100" cy="118" rx="9" ry="7" fill="' + INK + '"/><path d="M100 124 L100 134 M90 138 Q100 144 110 138" stroke="' + INK + '" stroke-width="3.5" fill="none" stroke-linecap="round"/>'
    '<path d="' + heart_path(148, 150, 0.26) + '" fill="#EA026A"/>', True)
add('Cute', 'diamond', '<path d="M52 70 L78 44 L122 44 L148 70 L100 160 Z" fill="#BDE7FF" stroke="#7FC4EE" stroke-width="5" stroke-linejoin="round"/>'
    '<path d="M52 70 L148 70 M78 44 L90 70 L100 160 L110 70 L122 44" stroke="#7FC4EE" stroke-width="4" fill="none" stroke-linejoin="round"/>' + sparkle(152, 40, 14, '#FFFFFF'), True)
add('Cute', 'disco_ball', '<defs><clipPath id="dc"><circle cx="100" cy="108" r="60"/></clipPath></defs><circle cx="100" cy="108" r="62" fill="#D8D8E0"/><g clip-path="url(#dc)">'
    + ''.join(f'<rect x="{x}" y="{y}" width="14" height="14" fill="{c}" />'
              for (x, y), c in zip([(x, y) for x in range(40, 160, 16) for y in range(48, 168, 16)],
                                   ['#F5F5FA', '#B9B9C8', '#E4E4EE', '#CFCFDD', '#FFE0EE', '#EDEDF5'] * 60))
    + '</g><circle cx="100" cy="108" r="62" fill="none" stroke="#9B9BAE" stroke-width="4"/><rect x="96" y="20" width="8" height="26" fill="#9B9BAE"/>'
    + sparkle(150, 60, 18, '#FFFFFF'), True)
add('Cute', 'shell', '<path d="M100 40 C150 40 176 100 150 150 L50 150 C24 100 50 40 100 40 Z" fill="#FFD3C2" stroke="#F0A38C" stroke-width="5"/>'
    + ''.join(f'<path d="M100 150 L{x} 52" stroke="#F0A38C" stroke-width="4"/>' for x in (46, 66, 84, 100, 116, 134, 154))
    + '<rect x="82" y="146" width="36" height="16" rx="6" fill="#F0A38C"/>', True)

# ---------------------------------------------------------------- Love
add('Love', 'heart_pink', f'<path d="{heart_path()}" fill="{PINK}"/><ellipse cx="62" cy="62" rx="12" ry="8" fill="#fff" opacity=".6" transform="rotate(-30 62 62)"/>', True)
add('Love', 'heart_puffy', f'<path d="{heart_path()}" fill="#FF9CC5"/><path d="{heart_path(100,104,0.8)}" fill="#FFC6DC"/><ellipse cx="66" cy="66" rx="14" ry="9" fill="#fff" opacity=".8" transform="rotate(-30 66 66)"/>', True)
add('Love', 'heart_outline', f'<path d="{heart_path()}" fill="none" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/><path d="{heart_path(104,96,0.93)}" fill="none" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')
add('Love', 'heart_scribble', f'<path d="{heart_path()}" fill="none" stroke="{PINK}" stroke-width="7" stroke-linejoin="round"/><path d="{heart_path(98,104,0.85)}" fill="none" stroke="{PINK}" stroke-width="4" stroke-linejoin="round"/><path d="{heart_path(102,98,0.95)}" fill="none" stroke="{PINK}" stroke-width="3"/>')
add('Love', 'hearts_trio', f'<path d="{heart_path(80,110,0.7)}" fill="{PINK}"/><path d="{heart_path(148,70,0.4)}" fill="{SOFT}"/><path d="{heart_path(150,150,0.28)}" fill="{BLUSH}"/>', True)
add('Love', 'heart_red', f'<path d="{heart_path()}" fill="#E0354F"/><ellipse cx="62" cy="62" rx="12" ry="8" fill="#fff" opacity=".55" transform="rotate(-30 62 62)"/>', True)
add('Love', 'heart_lilac', f'<path d="{heart_path()}" fill="{LAV}"/><ellipse cx="62" cy="62" rx="12" ry="8" fill="#fff" opacity=".6" transform="rotate(-30 62 62)"/>', True)
add('Love', 'heart_arrow', f'<path d="{heart_path(100,104,0.8)}" fill="{PINK}"/><path d="M20 150 L180 50" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="M180 50 L158 52 L170 70 Z" fill="{INK}"/><path d="M20 150 L30 132 M20 150 L38 146 M30 144 L40 126 M30 144 L48 140" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>', True)
add('Love', 'lips', '<path d="M24 100 C50 60 80 62 100 78 C120 62 150 60 176 100 C150 150 50 150 24 100 Z" fill="#E0354F"/><path d="M24 100 C60 108 140 108 176 100" stroke="#A5122F" stroke-width="5" fill="none"/><ellipse cx="70" cy="122" rx="14" ry="6" fill="#fff" opacity=".4"/>', True)
add('Love', 'love_letter', '<rect x="24" y="52" width="152" height="104" rx="10" fill="#FFF6EA" stroke="#E7C9B0" stroke-width="5"/><path d="M24 58 L100 116 L176 58" fill="none" stroke="#E7C9B0" stroke-width="5" stroke-linejoin="round"/>'
    f'<path d="{heart_path(100,112,0.26)}" fill="{PINK}"/>', True)
add('Love', 'heart_balloons', ''.join(f'<path d="M{x} {y+40} Q{x-6} {y+80} 100 180" stroke="{INK}" stroke-width="2.5" fill="none"/>' for x, y in ((62, 60), (100, 40), (140, 66)))
    + f'<path d="{heart_path(62,66,0.38)}" fill="{SOFT}"/><path d="{heart_path(100,46,0.42)}" fill="{PINK}"/><path d="{heart_path(140,72,0.36)}" fill="{LAV}"/>', True)
add('Love', 'kiss_marks', '<g transform="rotate(-15 70 80)"><path d="M30 80 C44 58 60 60 70 70 C80 60 96 58 110 80 C96 108 44 108 30 80 Z" fill="#E0354F"/></g>'
    '<g transform="rotate(12 130 132)"><path d="M92 132 C104 114 118 116 126 124 C134 116 148 114 160 132 C148 154 104 154 92 132 Z" fill="#EA026A"/></g>', True)

# ---------------------------------------------------------------- Flowers
add('Flowers', 'pink_flower', flower(100, 100, 5, 40, 32, 38, '#FF8DBB', '#FFD25C', 20, stroke='#F46AA4'), True)
add('Flowers', 'daisy', flower(100, 100, 14, 36, 11, 40, '#FFFFFF', '#FFC94A', 22, stroke='#EDE3DA'), True)
add('Flowers', 'white_blossom', flower(100, 100, 5, 38, 30, 36, '#FFFBF5', '#F6C35B', 14, stroke='#EAD9C7'), True)
add('Flowers', 'lilac_flower', flower(100, 100, 6, 34, 24, 36, '#C7A8F0', '#FFE38C', 16, stroke='#AF8BE2'), True)
add('Flowers', 'sunflower', flower(100, 100, 16, 40, 12, 48, '#FFC94A', '#6B4226', 32, stroke='#F2B230')
    + ''.join(f'<circle cx="{100+14*math.cos(a)}" cy="{100+14*math.sin(a)}" r="3" fill="#8A5A3C"/>' for a in [i*0.8 for i in range(8)]), True)
add('Flowers', 'tulip', '<path d="M100 186 L100 110" stroke="#6E9F6A" stroke-width="7"/><path d="M100 150 C70 140 60 120 62 104 C82 110 96 124 100 146 Z" fill="#8DBB88"/>'
    '<path d="M62 60 C62 110 86 124 100 124 C114 124 138 110 138 60 L120 80 L100 50 L80 80 Z" fill="#FF6FA5"/>', True)
add('Flowers', 'rose', '<circle cx="100" cy="92" r="52" fill="#E0354F"/><path d="M100 92 m-30 0 a30 30 0 1 0 60 0 a30 30 0 1 0 -60 0" fill="none" stroke="#A5122F" stroke-width="5"/>'
    '<path d="M86 86 C94 70 118 74 116 94 C114 108 92 110 90 96" fill="none" stroke="#A5122F" stroke-width="5" stroke-linecap="round"/>'
    '<path d="M60 140 C40 150 30 170 44 176 C60 170 70 156 76 142 Z M140 140 C160 150 170 170 156 176 C140 170 130 156 124 142 Z" fill="#6E9F6A"/>', True)
add('Flowers', 'cherry_blossom', ''.join(f'<path d="M100 100 C80 70 84 44 100 40 C116 44 120 70 100 100 Z" fill="#FFC2DA" stroke="#FF9CC5" stroke-width="3" transform="rotate({a} 100 100)"/>' for a in range(0, 360, 72))
    + '<circle cx="100" cy="100" r="10" fill="#FF6FA5"/>' + ''.join(f'<circle cx="{100+18*math.cos(math.radians(a))}" cy="{100+18*math.sin(math.radians(a))}" r="3" fill="#EA026A"/>' for a in range(18, 360, 72)), True)
add('Flowers', 'dried_bouquet', '<path d="M100 190 L70 70 M100 190 L100 60 M100 190 L130 70 M100 190 L150 96 M100 190 L52 100" stroke="#B08C5E" stroke-width="4"/>'
    + ''.join(f'<ellipse cx="{x}" cy="{y}" rx="9" ry="14" fill="{c}" transform="rotate({r} {x} {y})"/>' for x, y, c, r in
              [(70, 64, '#F1DDB5', -20), (62, 80, '#E9CF9E', 10), (100, 52, '#F4E3C3', 0), (92, 70, '#E9CF9E', 30), (130, 64, '#F1DDB5', 20), (138, 80, '#DDBB86', -10),
               (150, 92, '#E9CF9E', 30), (52, 96, '#F1DDB5', -30), (112, 72, '#DDBB86', -20)])
    + '<path d="M86 150 L114 150 L108 176 L92 176 Z" fill="#E8A87C"/>', True)
add('Flowers', 'leaf_sprig', '<path d="M100 186 C100 130 96 80 100 20" stroke="#6E9F6A" stroke-width="5" fill="none"/>'
    + ''.join(f'<ellipse cx="{100+s*22}" cy="{y}" rx="20" ry="9" fill="{SAGE}" transform="rotate({s*-35} {100+s*22} {y})"/>' for s, y in ((1, 50), (-1, 70), (1, 90), (-1, 110), (1, 130), (-1, 150))), True)
add('Flowers', 'palm_leaf', '<path d="M40 180 C70 130 110 90 170 30" stroke="#4E8A5C" stroke-width="6" fill="none"/>'
    + ''.join(f'<path d="M{40+t*130} {180-t*150} q{-30+t*10} {-10} {-50+t*20} {-40}" stroke="#6EAA7A" stroke-width="12" fill="none" stroke-linecap="round"/>'
              f'<path d="M{40+t*130} {180-t*150} q{25} {10} {50-t*10} {35}" stroke="#6EAA7A" stroke-width="12" fill="none" stroke-linecap="round"/>' for t in (0.2, 0.35, 0.5, 0.65, 0.8)), True)
add('Flowers', 'flower_smiley', flower(100, 100, 6, 36, 28, 40, '#FFB3CC', '#FFD25C', 34, stroke='#FF8DBB')
    + f'<circle cx="88" cy="96" r="5" fill="{INK}"/><circle cx="112" cy="96" r="5" fill="{INK}"/><path d="M88 110 Q100 122 112 110" stroke="{INK}" stroke-width="4" fill="none" stroke-linecap="round"/>', True)
add('Flowers', 'flower_crown', ''.join(flower(x, y, 5, 14, 11, 13, c, '#FFD25C', 6) for x, y, c in
                                       ((30, 120, '#FF8DBB'), (62, 92, '#FFFFFF'), (100, 80, '#C7A8F0'), (138, 92, '#FFFFFF'), (170, 120, '#FF8DBB')))
    + ''.join(f'<ellipse cx="{x}" cy="{y}" rx="10" ry="5" fill="{SAGE}" transform="rotate({r} {x} {y})"/>' for x, y, r in ((46, 112, -40), (82, 90, -15), (120, 90, 15), (154, 112, 40))), True)

# ---------------------------------------------------------------- Paper
add('Paper', 'tape_pink', tape('#FFB3CC', stripes('#FFFFFF')))
add('Paper', 'tape_dots', tape('#FFE0B8', dots('#FFFFFF')))
add('Paper', 'tape_grid', tape('#CFE3D0', grid('#FFFFFF')))
add('Paper', 'tape_lilac', tape('#D9C6F5', stripes('#FFFFFF')))
add('Paper', 'tape_kraft', tape('#D9B991', dots('#C29F74')))
add('Paper', 'polaroid', '<g transform="rotate(-6 100 100)"><rect x="40" y="26" width="120" height="146" fill="#FFFFFF" stroke="#E6DDD6" stroke-width="3"/><rect x="50" y="36" width="100" height="100" fill="#F3E1E8"/>'
    + sparkle(100, 86, 18, '#FFFFFF') + '</g>', True)
add('Paper', 'film_strip', '<g transform="rotate(-10 100 100)"><rect x="14" y="62" width="172" height="76" fill="#1E1A1C"/>'
    + ''.join(f'<rect x="{x}" y="68" width="8" height="8" rx="2" fill="#fff"/><rect x="{x}" y="124" width="8" height="8" rx="2" fill="#fff"/>' for x in range(20, 184, 16))
    + ''.join(f'<rect x="{x}" y="82" width="46" height="36" fill="{c}"/>' for x, c in ((22, '#FFC2DA'), (77, '#C7A8F0'), (132, '#FFE0B8'))) + '</g>', True)
add('Paper', 'torn_paper', '<path d="M10 70 L22 62 L34 72 L48 60 L60 70 L74 62 L88 72 L102 60 L116 70 L130 62 L144 72 L158 60 L172 70 L190 64 L190 136 L176 144 L162 134 L148 146 L134 136 L120 144 L106 134 L92 146 L78 136 L64 144 L50 134 L36 146 L22 136 L10 142 Z" fill="#FFFFFF" stroke="#EDE4DE" stroke-width="2"/>', True)
add('Paper', 'paper_clip', '<path d="M86 30 L86 140 A22 22 0 0 0 130 140 L130 50 A14 14 0 0 0 102 50 L102 132" stroke="#C7A8F0" stroke-width="9" fill="none" stroke-linecap="round"/>')
add('Paper', 'push_pin', '<path d="M100 120 L92 184" stroke="#9B9BAE" stroke-width="5" stroke-linecap="round"/><ellipse cx="100" cy="110" rx="44" ry="14" fill="#D6005F"/><rect x="80" y="44" width="40" height="66" rx="10" fill="#EA026A"/><ellipse cx="100" cy="44" rx="34" ry="12" fill="#FF5C9E"/>', True)
add('Paper', 'note_card', '<g transform="rotate(4 100 100)"><rect x="30" y="40" width="140" height="120" rx="6" fill="#FFF6EA" stroke="#EAD9C7" stroke-width="3"/>'
    + ''.join(f'<rect x="44" y="{y}" width="112" height="2.5" fill="#F3CADB"/>' for y in range(70, 150, 16)) + '<rect x="30" y="40" width="140" height="18" fill="#FFC2DA"/></g>', True)
add('Paper', 'ribbon_banner', '<path d="M8 90 L40 90 L40 140 L24 124 L8 140 Z M192 90 L160 90 L160 140 L176 124 L192 140 Z" fill="#D6005F"/><path d="M30 70 L170 70 L170 124 L30 124 Z" fill="#FF5C9E"/>'
    + word('love', 'Pacifico', 36, '#FFFFFF', 'none', 0, 0, 110), True)
add('Paper', 'vintage_camera', '<rect x="22" y="62" width="156" height="104" rx="14" fill="#8A6A4C"/><rect x="22" y="84" width="156" height="60" fill="#5E4632"/><rect x="36" y="46" width="40" height="22" rx="4" fill="#8A6A4C"/>'
    '<circle cx="100" cy="114" r="40" fill="#D9C7A8"/><circle cx="100" cy="114" r="30" fill="#3B2B1F"/><circle cx="100" cy="114" r="18" fill="#6E5A7E"/><circle cx="92" cy="106" r="6" fill="#fff" opacity=".6"/>'
    '<rect x="140" y="70" width="24" height="12" rx="3" fill="#D9C7A8"/>', True)
add('Paper', 'label_tag', '<path d="M40 60 L150 60 L180 100 L150 140 L40 140 Q30 140 30 130 L30 70 Q30 60 40 60 Z" fill="#FFF6EA" stroke="#D9B991" stroke-width="4"/><circle cx="156" cy="100" r="7" fill="#fff" stroke="#D9B991" stroke-width="4"/>'
    + word('xoxo', 'Caveat', 44, PINK, 'none', 0, 0, 114), True)
add('Paper', 'stamp_love', '<rect x="36" y="36" width="128" height="128" fill="#FFFFFF"/>'
    + ''.join(f'<circle cx="{x}" cy="36" r="6" fill="#EAD9C7"/><circle cx="{x}" cy="164" r="6" fill="#EAD9C7"/><circle cx="36" cy="{x}" r="6" fill="#EAD9C7"/><circle cx="164" cy="{x}" r="6" fill="#EAD9C7"/>' for x in range(36, 170, 16))
    + '<rect x="48" y="48" width="104" height="104" fill="#FFC2DA"/>' + f'<path d="{heart_path(100,104,0.45)}" fill="{PINK}"/>', True)

# ---------------------------------------------------------------- Doodles
add('Doodles', 'arrow_curly', f'<path d="M24 150 C60 150 60 90 96 96 C130 102 110 140 94 124 C80 110 120 60 170 56" stroke="{INK}" stroke-width="5" fill="none" stroke-linecap="round"/><path d="M152 46 L172 56 L156 72" stroke="{INK}" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
add('Doodles', 'swirl', f'<path d="M100 100 m0 -8 a8 8 0 1 1 -8 8 a16 16 0 1 1 16 16 a26 26 0 1 1 -26 -26 a38 38 0 1 1 38 38 a52 52 0 1 1 -52 -52" stroke="{PINK}" stroke-width="5" fill="none" stroke-linecap="round"/>')
add('Doodles', 'underline', f'<path d="M20 110 C60 96 100 104 140 96 C156 94 170 96 182 100 M30 126 C80 114 130 120 176 112" stroke="{PINK}" stroke-width="7" fill="none" stroke-linecap="round"/>')
add('Doodles', 'circle_scribble', f'<path d="M150 60 C120 30 50 36 36 90 C24 140 90 172 142 150 C180 132 176 76 128 56 C110 50 80 52 68 60" stroke="{PINK}" stroke-width="5" fill="none" stroke-linecap="round"/>')
add('Doodles', 'stars_doodle', star5(64, 70, 34, 15, 'none', INK, 4) + star5(140, 120, 26, 11, 'none', INK, 4) + star5(150, 50, 14, 6, 'none', INK, 3))
add('Doodles', 'hearts_doodle', f'<path d="{heart_path(70,80,0.45)}" fill="none" stroke="{INK}" stroke-width="4"/><path d="{heart_path(136,128,0.36)}" fill="none" stroke="{INK}" stroke-width="4"/><path d="{heart_path(150,56,0.2)}" fill="none" stroke="{INK}" stroke-width="3"/>')
add('Doodles', 'sparkle_lines', ''.join(f'<path d="M100 100 m{30*math.cos(math.radians(a))} {30*math.sin(math.radians(a))} l{30*math.cos(math.radians(a))} {30*math.sin(math.radians(a))}" stroke="{GOLD}" stroke-width="7" stroke-linecap="round"/>' for a in range(0, 360, 45)))
add('Doodles', 'music_notes', f'<path d="M70 150 L70 60 L150 44 L150 130" stroke="{INK}" stroke-width="7" fill="none" stroke-linejoin="round"/><ellipse cx="56" cy="152" rx="18" ry="13" fill="{INK}"/><ellipse cx="136" cy="134" rx="18" ry="13" fill="{INK}"/><path d="M70 76 L150 60" stroke="{INK}" stroke-width="7"/>')
add('Doodles', 'speech_hi', '<path d="M30 40 L170 40 Q182 40 182 52 L182 120 Q182 132 170 132 L80 132 L50 164 L56 132 L30 132 Q18 132 18 120 L18 52 Q18 40 30 40 Z" fill="#FFFFFF" stroke="' + INK + '" stroke-width="5" stroke-linejoin="round"/>'
    + word('hi!', 'Pacifico', 52, PINK, 'none', 0, 0, 106), True)
add('Doodles', 'speech_omg', '<path d="M100 30 C160 30 184 60 184 90 C184 124 150 146 100 146 C90 146 80 145 70 142 L36 170 L46 132 C26 120 16 106 16 90 C16 60 40 30 100 30 Z" fill="#FFE38C" stroke="' + INK + '" stroke-width="5" stroke-linejoin="round"/>'
    + word('OMG', 'BebasNeue', 60, INK, 'none', 0, 0, 110), True)
add('Doodles', 'squiggle', f'<path d="M16 100 q14 -28 28 0 t28 0 t28 0 t28 0 t28 0 t28 0" stroke="{LAV}" stroke-width="8" fill="none" stroke-linecap="round"/>')
add('Doodles', 'checkmark', '<circle cx="100" cy="100" r="70" fill="#A8E6B8"/><path d="M64 102 L90 128 L140 72" stroke="#fff" stroke-width="14" fill="none" stroke-linecap="round" stroke-linejoin="round"/>', True)

# ---------------------------------------------------------------- Food & Fun
add('Food', 'cherries', '<path d="M70 130 C80 80 100 50 130 34 M130 130 C128 90 128 60 130 34" stroke="#6E9F6A" stroke-width="5" fill="none"/><ellipse cx="146" cy="40" rx="20" ry="9" fill="#8DBB88" transform="rotate(-20 146 40)"/>'
    '<circle cx="66" cy="140" r="30" fill="#E0354F"/><circle cx="130" cy="140" r="30" fill="#EA026A"/><ellipse cx="56" cy="130" rx="8" ry="5" fill="#fff" opacity=".6"/><ellipse cx="120" cy="130" rx="8" ry="5" fill="#fff" opacity=".6"/>', True)
add('Food', 'strawberry', '<path d="M100 176 C40 150 34 80 60 62 C80 50 120 50 140 62 C166 80 160 150 100 176 Z" fill="#F0435F"/>'
    + ''.join(f'<ellipse cx="{x}" cy="{y}" rx="3" ry="5" fill="#FFE38C"/>' for x, y in ((74, 90), (100, 84), (126, 90), (86, 116), (114, 116), (100, 142), (70, 124), (130, 124)))
    + '<path d="M60 64 L80 40 L92 58 L100 30 L108 58 L120 40 L140 64 Q100 80 60 64 Z" fill="#6EAA7A"/>', True)
add('Food', 'coffee', '<path d="M50 70 L150 70 L140 170 Q138 180 128 180 L72 180 Q62 180 60 170 Z" fill="#FFFFFF" stroke="#D9C7B8" stroke-width="4"/><rect x="44" y="56" width="112" height="18" rx="8" fill="#8A5A3C"/>'
    '<rect x="56" y="104" width="90" height="40" fill="#F3CADB"/>' + f'<path d="{heart_path(100,126,0.16)}" fill="{PINK}"/>'
    + '<path d="M84 40 C76 30 92 22 84 12 M104 40 C96 30 112 22 104 12" stroke="#C9B3A5" stroke-width="4" fill="none" stroke-linecap="round"/>', True)
add('Food', 'boba', '<path d="M52 60 L148 60 L136 180 Q134 188 126 188 L74 188 Q66 188 64 180 Z" fill="#F4D8C4" stroke="#D9B08C" stroke-width="4"/><path d="M48 60 Q100 20 152 60 Z" fill="#FFFFFF" stroke="#D9B08C" stroke-width="4"/>'
    '<rect x="108" y="4" width="12" height="80" rx="4" fill="' + PINK + '" transform="rotate(12 114 44)"/>'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="7" fill="#3B2B1F"/>' for x, y in ((80, 170), (98, 174), (116, 170), (90, 158), (108, 158), (124, 160))), True)
add('Food', 'lemon', '<circle cx="100" cy="100" r="70" fill="#FFE38C" stroke="#F6C94A" stroke-width="8"/>' + ''.join(f'<path d="M100 100 L{100+58*math.cos(math.radians(a))} {100+58*math.sin(math.radians(a))} A58 58 0 0 1 {100+58*math.cos(math.radians(a+45))} {100+58*math.sin(math.radians(a+45))} Z" fill="#FFF3B8" stroke="#FFFFFF" stroke-width="4"/>' for a in range(0, 360, 45)), True)
add('Food', 'ice_cream', '<path d="M64 100 L100 190 L136 100 Z" fill="#E8B478"/><path d="M70 110 L128 110 M76 126 L122 126 M84 144 L116 144" stroke="#C98F4E" stroke-width="3"/>'
    '<circle cx="78" cy="92" r="28" fill="#FFB3CC"/><circle cx="122" cy="92" r="28" fill="#FFF3E6"/><circle cx="100" cy="62" r="30" fill="#C7A8F0"/><circle cx="100" cy="30" r="10" fill="#E0354F"/>', True)
add('Food', 'cake_slice', '<path d="M30 150 L170 150 L170 90 L30 120 Z" fill="#FFE0EE"/><path d="M30 120 L170 90 L150 70 Z" fill="#FFB3CC"/><path d="M30 136 L170 118" stroke="#FF8DBB" stroke-width="8"/><circle cx="148" cy="62" r="12" fill="#E0354F"/>', True)
add('Food', 'donut', '<circle cx="100" cy="100" r="70" fill="#E8B478"/><path d="M100 36 C150 36 170 76 164 104 C156 90 140 96 132 110 C120 94 96 110 84 118 C70 100 44 112 36 104 C30 76 50 36 100 36 Z" fill="#FF8DBB"/><circle cx="100" cy="100" r="22" fill="#fff" opacity="0"/>'
    '<circle cx="100" cy="100" r="22" fill="#FFFFFF"/>' + ''.join(f'<rect x="{x}" y="{y}" width="12" height="4" rx="2" fill="{c}" transform="rotate({r} {x} {y})"/>' for x, y, c, r in ((70, 60, '#FFE38C', 30), (120, 56, '#8EC5F0', -20), (140, 84, '#fff', 60), (60, 90, '#A8E6B8', -40), (96, 50, '#fff', 10))), True)
add('Food', 'popcorn', '<path d="M50 80 L150 80 L136 180 L64 180 Z" fill="#FFFFFF"/>' + ''.join(f'<rect x="{x}" y="80" width="12" height="100" fill="#EA026A" transform="skewX(0)"/>' for x in (56, 80, 104, 128))
    + ''.join(f'<circle cx="{x}" cy="{y}" r="16" fill="#FFF3C8"/>' for x, y in ((58, 72), (82, 60), (106, 64), (130, 58), (146, 72), (94, 44), (120, 40))), True)

# ---------------------------------------------------------------- Words
def pill(text, bg, fg, font='Poppins', size=34, rot=-6, w=150):
    return (f'<g transform="rotate({rot} 100 100)"><rect x="{100-w/2}" y="72" width="{w}" height="56" rx="28" fill="{bg}"/>'
            + word(text, font, size, fg, 'none', 0, 0, 112) + '</g>')

add('Words', 'cute', word('cute', 'Pacifico', 70, PINK, '#FFFFFF', 12, -8))
add('Words', 'xoxo', word('xoxo', 'Caveat', 80, '#E0354F', '#FFFFFF', 10, -6))
add('Words', 'vibes', word('vibes', 'Lobster', 70, '#FFFFFF', PINK, 12, -6))
add('Words', 'hello', word('hello', 'Righteous', 60, '#FFB547', INK, 10, -4))
add('Words', 'love_you', word('love you', 'GreatVibes', 64, PINK, '#FFFFFF', 10, -6))
add('Words', 'photo_dump', pill('photo dump', INK, '#FFFFFF', 'Poppins', 24, -4, 176))
add('Words', 'core_memory', pill('core memory', '#FFC2DA', INK, 'Poppins', 22, 5, 176))
add('Words', 'yay', word('yay!', 'Fredoka', 76, '#FFE38C', INK, 10, -8))
add('Words', 'besties', word('besties', 'Pacifico', 54, '#C7A8F0', '#FFFFFF', 12, -6))
add('Words', 'mood', pill('mood', PINK, '#FFFFFF', 'BebasNeue', 42, -8, 120))
add('Words', 'summer', word('summer', 'DancingScript', 66, '#FFB547', '#FFFFFF', 12, -6))
add('Words', 'self_love', word('self love', 'Sacramento', 70, PINK, '#FFFFFF', 10, -4))
add('Words', 'good_vibes', word('good vibes', 'ShadowsIntoLight', 50, INK, '#FFE38C', 14, -4))
add('Words', 'stay_wild', word('STAY WILD', 'BebasNeue', 54, SAGE, '#FFFFFF', 10, 0, ls=3))
add('Words', 'omg_wow', word('WOW', 'Monoton', 64, PINK, 'none', 0, -6))
add('Words', 'bestie_day', pill('best day ever', '#FFFFFF', PINK, 'Poppins', 20, 4, 180))
add('Words', 'thank_you', word('thank you', 'Parisienne', 56, INK, '#FFFFFF', 10, -4))
add('Words', 'happy_bday', word('happy bday', 'Pacifico', 42, '#FFFFFF', '#FF8DBB', 12, -6))

# ------------------------------------------------------------------ render
import base64
def _b64(f):
    return base64.b64encode(open(f"{FONTS}/{f}.ttf", "rb").read()).decode()
FONT_FACES = ''.join(
    f"@font-face{{font-family:'{n}';src:url(data:font/ttf;base64,{_b64(f)});}}"
    for n, f in [('Pacifico', 'Pacifico'), ('Caveat', 'Caveat'), ('Lobster', 'Lobster'), ('Righteous', 'Righteous'),
                 ('GreatVibes', 'GreatVibes'), ('Poppins', 'PoppinsBold'), ('Fredoka', 'Fredoka'), ('BebasNeue', 'BebasNeue'),
                 ('DancingScript', 'DancingScript'), ('Sacramento', 'Sacramento'), ('ShadowsIntoLight', 'ShadowsIntoLight'),
                 ('Monoton', 'Monoton'), ('Parisienne', 'Parisienne')])

DIECUT = '''<filter id="die" x="-20%" y="-20%" width="140%" height="140%">
<feMorphology in="SourceAlpha" operator="dilate" radius="6" result="d"/>
<feFlood flood-color="#ffffff"/><feComposite in2="d" operator="in" result="w"/>
<feGaussianBlur in="d" stdDeviation="3" result="b"/><feOffset in="b" dy="2" result="bo"/>
<feFlood flood-color="#000" flood-opacity=".18"/><feComposite in2="bo" operator="in" result="s"/>
<feMerge><feMergeNode in="s"/><feMergeNode in="w"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'''

def page(svg, diecut):
    body = f'<g filter="url(#die)">{svg}</g>' if diecut else svg
    return (f"<html><head><style>{FONT_FACES} html,body{{margin:0;background:transparent}}</style></head><body>"
            f'<svg id="s" xmlns="http://www.w3.org/2000/svg" viewBox="-10 -10 220 220" width="360" height="360">'
            f'<defs>{DIECUT}</defs>{body}</svg></body></html>')

os.makedirs(OUT, exist_ok=True)
catalog = {}
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(device_scale_factor=1)
    for (cat, name), (svg, diecut) in S.items():
        d = os.path.join(OUT, cat.lower())
        os.makedirs(d, exist_ok=True)
        pg.set_content(page(svg, diecut))
        pg.evaluate('document.fonts.ready.then(() => true)')
        pg.wait_for_timeout(80)
        pg.evaluate('''() => {
          for (const t of document.querySelectorAll('text')) {
            const w = t.getBBox().width;
            const max = t.closest('g[transform]') && t.parentNode.querySelector('rect') ? 150 : 196;
            if (w > max) {
              const fs = parseFloat(t.getAttribute('font-size'));
              t.setAttribute('font-size', (fs * max / w).toFixed(1));
            }
          }
        }''')
        pg.locator('#s').screenshot(path=os.path.join(d, name + '.png'), omit_background=True)
        catalog.setdefault(cat, []).append(f'assets/stickers/{cat.lower()}/{name}.png')
    b.close()

lines = ['// GENERATED by the sticker build script. Aesthetic sticker pack.', '',
         'class StickerCategory {', '  const StickerCategory(this.name, this.assets);',
         '  final String name;', '  final List<String> assets;', '}', '',
         'const List<StickerCategory> stickerCategories = [']
for cat, assets in catalog.items():
    lines.append(f"  StickerCategory('{cat}', [")
    lines += [f"    '{a}'," for a in assets]
    lines.append('  ]),')
lines.append('];')
open(os.path.join(APP, 'lib/data/sticker_data.dart'), 'w').write('\n'.join(lines) + '\n')
print('stickers:', sum(len(v) for v in catalog.values()), {k: len(v) for k, v in catalog.items()})

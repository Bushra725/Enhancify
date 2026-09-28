"""Single source of truth for the avatar artwork.

Writes lib/avatar/avatar_parts.dart (used by the Flutter painter) and renders
preview PNGs with Chromium so the art can be checked visually.
Coordinates are in a 200 x 240 box. Fill values are either '#RRGGBB' or a
color role resolved at runtime: skin, skinShade, hair, hairShade, eye, lip,
outfit, outfitShade, blush, ink, white, glasses, accent.
"""
import json, os, sys, math

APP = sys.argv[1]
PREVIEW = sys.argv[2] if len(sys.argv) > 2 else None


def P(d, fill, stroke=None, sw=0, op=1.0):
    return {'d': d, 'fill': fill, 'stroke': stroke, 'sw': sw, 'op': op}


def ellipse(cx, cy, rx, ry):
    return (f'M{cx-rx} {cy} A{rx} {ry} 0 1 0 {cx+rx} {cy} A{rx} {ry} 0 1 0 {cx-rx} {cy} Z')


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def heart(cx, cy, s):
    pts = [(0, 70), (-60, 25), (-85, -10), (-65, -45), (-45, -78), (-10, -70), (0, -42),
           (10, -70), (45, -78), (65, -45), (85, -10), (60, 25), (0, 70)]
    q = lambda i: f"{cx + pts[i][0]*s:.1f} {cy + pts[i][1]*s:.1f}"
    return f"M{q(0)} C{q(1)} {q(2)} {q(3)} C{q(4)} {q(5)} {q(6)} C{q(7)} {q(8)} {q(9)} C{q(10)} {q(11)} {q(12)} Z"

LX, RX, EY = 78, 122, 102  # eye centers

# ------------------------------------------------------------------ body
body = {
    'tee': [P('M34 240 C34 196 58 176 86 172 L114 172 C142 176 166 196 166 240 Z', 'outfit'),
            P('M86 172 C90 184 110 184 114 172 Z', 'skin')],
    'hoodie': [P('M30 240 C30 194 56 172 84 168 L116 168 C144 172 170 194 170 240 Z', 'outfit'),
               P('M72 172 C78 196 122 196 128 172 C118 178 82 178 72 172 Z', 'outfitShade'),
               P('M92 190 L90 214 M108 190 L110 214', 'none', 'outfitShade', 3)],
    'shirt': [P('M34 240 C34 196 58 176 86 172 L114 172 C142 176 166 196 166 240 Z', 'outfit'),
              P('M86 172 L100 196 L114 172 Z', 'skin'),
              P('M86 170 L100 196 L76 190 Z M114 170 L100 196 L124 190 Z', '#FFFFFF'),
              P('M100 198 L100 240', 'none', 'outfitShade', 2.5),
              P(circle(100, 212, 2.2), 'outfitShade'), P(circle(100, 228, 2.2), 'outfitShade')],
    'turtleneck': [P('M34 240 C34 196 58 176 86 172 L114 172 C142 176 166 196 166 240 Z', 'outfit'),
                   P('M84 158 L116 158 L118 182 C106 188 94 188 82 182 Z', 'outfitShade')],
    'jacket': [P('M34 240 C34 196 58 176 86 172 L114 172 C142 176 166 196 166 240 Z', '#F4F1EE'),
               P('M86 172 C90 184 110 184 114 172 Z', 'skin'),
               P('M34 240 C34 196 58 176 84 170 L90 186 L96 240 Z', 'outfit'),
               P('M166 240 C166 196 142 176 116 170 L110 186 L104 240 Z', 'outfit'),
               P('M84 170 L90 186 L80 200 M116 170 L110 186 L120 200', 'none', 'outfitShade', 3),
               P('M60 214 L60 240 M140 214 L140 240', 'none', 'outfitShade', 2.5)],
    'polo': [P('M34 240 C34 196 58 176 86 172 L114 172 C142 176 166 196 166 240 Z', 'outfit'),
             P('M86 172 C90 180 110 180 114 172 Z', 'skin'),
             P('M84 168 L94 188 L100 176 L106 188 L116 168 L108 172 L100 176 L92 172 Z', 'outfitShade'),
             P('M100 178 L100 204', 'none', 'outfitShade', 2.2),
             P(circle(100, 186, 1.8), '#FFFFFF'), P(circle(100, 196, 1.8), '#FFFFFF')],
    'suit': [P('M34 240 C34 196 58 176 86 172 L114 172 C142 176 166 196 166 240 Z', 'outfit'),
             P('M86 172 L100 206 L114 172 Z', '#FFFFFF'),
             P('M96 178 L104 178 L107 214 L100 224 L93 214 Z', 'accent'),
             P('M86 170 L100 206 L78 188 Z M114 170 L100 206 L122 188 Z', 'outfitShade'),
             P(circle(100, 226, 2), 'outfitShade')],
    'kurta': [P('M36 240 C36 196 60 178 86 172 L114 172 C140 178 164 196 164 240 Z', 'outfit'),
              P('M86 172 C90 178 110 178 114 172 L112 166 L88 166 Z', 'outfitShade'),
              P('M100 172 L100 210', 'none', 'outfitShade', 2.4),
              P(circle(100, 182, 1.8), 'accent'), P(circle(100, 192, 1.8), 'accent'), P(circle(100, 202, 1.8), 'accent')],
    'dress': [P('M40 240 C42 200 62 184 80 182 L120 182 C138 184 158 200 160 240 Z', 'outfit'),
              P('M80 182 L84 170 M120 182 L116 170', 'none', 'outfit', 5),
              P('M80 182 C92 190 108 190 120 182', 'none', 'outfitShade', 2.5)],
}
neck = [P('M86 132 L114 132 L116 176 C106 182 94 182 84 176 Z', 'skinShade')]

# ------------------------------------------------------------------ head
heads = {
    'oval': 'M100 32 C136 32 158 60 158 96 C158 136 132 162 100 162 C68 162 42 136 42 96 C42 60 64 32 100 32 Z',
    'round': 'M100 34 C140 34 162 62 162 100 C162 138 136 160 100 160 C64 160 38 138 38 100 C38 62 60 34 100 34 Z',
    'square': 'M100 34 C140 34 158 56 158 92 L156 124 C152 148 128 162 100 162 C72 162 48 148 44 124 L42 92 C42 56 60 34 100 34 Z',
    'heart': 'M100 34 C138 34 160 58 158 94 C156 126 132 160 100 164 C68 160 44 126 42 94 C40 58 62 34 100 34 Z',
    'jaw': 'M100 34 C140 34 158 58 158 92 L156 120 C154 140 138 156 118 163 L82 163 C62 156 46 140 44 120 L42 92 C42 58 60 34 100 34 Z',
}
ears = [P(ellipse(44, 104, 9, 14), 'skin'), P(ellipse(156, 104, 9, 14), 'skin'),
        P(ellipse(45, 104, 4, 7), 'skinShade'), P(ellipse(155, 104, 4, 7), 'skinShade')]

# ------------------------------------------------------------------ hair (back layers go behind the head)
hair_back = {
    'long': [P('M42 88 C36 40 68 24 100 24 C134 24 166 40 158 90 L164 196 C142 208 58 208 36 196 Z', 'hair')],
    'wavy': [P('M40 90 C34 40 68 24 100 24 C134 24 168 40 160 90 C170 120 156 140 168 168 C176 190 150 206 128 198 L72 198 C50 206 24 190 32 168 C44 140 30 120 40 90 Z', 'hair')],
    'bob': [P('M40 92 C36 42 68 26 100 26 C134 26 166 42 160 92 L162 148 C150 158 136 156 130 150 L70 150 C64 156 50 158 38 148 Z', 'hair')],
    'ponytail': [P('M134 46 C176 44 184 104 170 150 C166 170 150 176 148 160 C160 120 156 76 128 58 Z', 'hair')],
    'bun': [P(circle(100, 30, 24), 'hair'), P('M84 30 C90 20 110 20 116 30', 'none', 'hairShade', 3)],
    'braids': [P('M44 96 L40 190 C40 204 60 204 60 190 L62 110 Z', 'hair'), P('M156 96 L160 190 C160 204 140 204 140 190 L138 110 Z', 'hair'),
               P('M42 130 L60 134 M42 150 L60 154 M42 170 L60 174 M158 130 L140 134 M158 150 L140 154 M158 170 L140 174', 'none', 'hairShade', 3)],
    'manbun': [P(circle(100, 26, 15), 'hair'), P('M90 26 C94 18 106 18 110 26', 'none', 'hairShade', 2.5)],
    'afro': [P('M100 8 C150 8 184 40 180 90 C186 130 160 150 150 140 L50 140 C40 150 14 130 20 90 C16 40 50 8 100 8 Z', 'hair')],
    'hijab': [P('M100 22 C146 22 172 56 170 104 C168 150 160 176 176 204 L24 204 C40 176 32 150 30 104 C28 56 54 22 100 22 Z', 'hair'),
              P('M30 204 C60 190 140 190 170 204 L172 240 L28 240 Z', 'hair')],
}
hair_front = {
    'short': [P('M44 98 C38 50 66 28 100 28 C136 28 164 48 156 98 C152 76 140 62 124 58 C110 72 80 74 62 66 C52 76 46 86 44 98 Z', 'hair')],
    'buzz': [P('M46 90 C44 50 70 32 100 32 C132 32 156 50 154 90 C140 70 122 62 100 62 C78 62 60 70 46 90 Z', 'hair', None, 0, 0.9)],
    'sidepart': [P('M42 102 C34 48 66 26 102 26 C138 26 166 50 158 100 C156 78 146 62 132 56 C120 50 96 48 74 64 C60 74 50 86 42 102 Z', 'hair'),
                 P('M74 64 C92 50 116 48 132 56', 'none', 'hairShade', 3)],
    'curly': [P(''.join(f'M{x} {y} m-15 0 a15 15 0 1 0 30 0 a15 15 0 1 0 -30 0 ' for x, y in
                        [(52, 78), (62, 56), (82, 42), (104, 38), (126, 44), (144, 58), (152, 80), (72, 64), (94, 56), (116, 58), (134, 70)]), 'hair')],
    'long': [P('M42 110 C36 50 66 26 100 26 C136 26 164 50 158 110 C152 80 132 60 110 56 C104 70 84 82 58 84 C50 92 46 100 42 110 Z', 'hair')],
    'wavy': [P('M42 108 C36 50 66 26 100 26 C136 26 164 50 158 108 C150 80 136 64 116 60 C112 74 96 80 82 74 C70 84 54 90 42 108 Z', 'hair')],
    'bob': [P('M42 104 C36 50 66 28 100 28 C136 28 164 50 158 104 C150 84 142 74 132 70 L68 70 C58 74 50 84 42 104 Z', 'hair'),
            P('M68 70 L132 70', 'none', 'hairShade', 2)],
    'ponytail': [P('M44 96 C40 50 68 30 100 30 C134 30 160 50 156 96 C150 70 128 56 100 56 C74 56 52 70 44 96 Z', 'hair')],
    'bun': [P('M44 96 C40 50 68 32 100 32 C134 32 160 50 156 96 C150 70 128 58 100 58 C74 58 52 70 44 96 Z', 'hair')],
    'braids': [P('M44 96 C40 50 68 30 100 30 C134 30 160 50 156 96 C146 72 124 60 100 60 C78 60 56 70 44 96 Z', 'hair'),
               P('M100 32 L100 60', 'none', 'hairShade', 2.5)],
    'afro': [P('M40 92 C44 72 58 60 100 58 C142 60 156 72 160 92 C168 60 150 30 100 30 C50 30 32 60 40 92 Z', 'hair')],
    'bald': [],
    'quiff': [P('M44 96 C38 56 60 30 90 24 C104 12 132 10 146 22 C156 32 150 42 142 44 C154 56 158 76 156 96 C152 74 140 62 124 58 C104 52 80 56 62 66 C52 74 46 84 44 96 Z', 'hair'),
              P('M96 26 C112 18 132 18 142 28', 'none', 'hairShade', 2.5)],
    'spiky': [P('M44 96 C42 72 46 54 54 44 L54 24 L68 36 L76 14 L88 32 L100 10 L110 30 L124 14 L128 34 L146 24 L144 44 C154 58 158 76 156 96 C150 72 132 60 100 60 C72 60 52 72 44 96 Z', 'hair')],
    'fade': [P('M50 80 C48 46 72 30 100 30 C128 30 152 46 150 80 C138 64 120 58 100 58 C80 58 62 64 50 80 Z', 'hair'),
             P('M44 104 C42 90 46 80 52 74 L56 92 Z M156 104 C158 90 154 80 148 74 L144 92 Z', 'hair', None, 0, 0.45)],
    'slick': [P('M44 94 C40 50 68 28 100 28 C134 28 160 50 156 94 C152 70 142 58 128 54 C112 48 88 48 72 54 C58 58 48 70 44 94 Z', 'hair'),
              P('M72 40 C90 34 112 34 130 40 M66 48 C86 42 116 42 136 48', 'none', 'hairShade', 2.2)],
    'fringe': [P('M42 100 C36 48 66 26 100 26 C136 26 164 48 158 100 C156 86 150 78 146 76 L136 72 L126 78 L114 72 L100 78 L86 72 L74 78 L62 72 L54 76 C50 78 44 86 42 100 Z', 'hair')],
    'manbun': [P('M44 96 C40 50 68 32 100 32 C134 32 160 50 156 96 C150 70 128 56 100 56 C74 56 52 70 44 96 Z', 'hair'),
               P('M100 34 L100 56', 'none', 'hairShade', 2)],
    'hijab': [P('M40 104 C40 56 66 34 100 34 C134 34 160 56 160 104 C158 64 134 48 100 48 C66 48 42 64 40 104 Z', 'hairShade', None, 0, 0.55)],
}
hair_face_cut = {  # hijab frames the face: draw an outline of the fabric around it
    'hijab': [P('M40 104 C38 150 70 176 100 176 C130 176 162 150 160 104', 'none', 'hairShade', 3)],
}

# ------------------------------------------------------------------ face
def eye_open(style):
    out = []
    for x in (LX, RX):
        if style == 'almond':
            out.append(P(f'M{x-12} {EY} C{x-6} {EY-9} {x+6} {EY-9} {x+12} {EY} C{x+6} {EY+8} {x-6} {EY+8} {x-12} {EY} Z', 'white'))
        else:
            out.append(P(ellipse(x, EY, 9, 10.5), 'white'))
        out.append(P(circle(x, EY + 1, 6.4), 'eye'))
        out.append(P(circle(x, EY + 1, 3.2), 'ink'))
        out.append(P(circle(x + 2.2, EY - 1.6, 1.9), 'white'))
        if style == 'lashes':
            s = 1 if x > 100 else -1
            out.append(P(f'M{x+s*8} {EY-6} L{x+s*13} {EY-10} M{x+s*9} {EY-2} L{x+s*14} {EY-4}', 'none', 'ink', 2.2))
        out.append(P(f'M{x-10} {EY-3} C{x-5} {EY-11} {x+5} {EY-11} {x+10} {EY-3}', 'none', 'ink', 2.4))
    return out

eyes = {k: eye_open(k) for k in ('round', 'almond', 'lashes')}

brows = {
    'soft': [P(f'M{LX-11} 86 C{LX-4} 81 {LX+4} 81 {LX+11} 85', 'none', 'hairShade', 3.4), P(f'M{RX-11} 85 C{RX-4} 81 {RX+4} 81 {RX+11} 86', 'none', 'hairShade', 3.4)],
    'thick': [P(f'M{LX-12} 86 C{LX-4} 79 {LX+6} 79 {LX+12} 84 L{LX+12} 88 C{LX+4} 85 {LX-4} 86 {LX-12} 90 Z', 'hairShade'),
              P(f'M{RX+12} 86 C{RX+4} 79 {RX-6} 79 {RX-12} 84 L{RX-12} 88 C{RX-4} 85 {RX+4} 86 {RX+12} 90 Z', 'hairShade')],
    'straight': [P(f'M{LX-13} 84 L{LX+12} 83 L{LX+12} 88 L{LX-13} 89 Z', 'hairShade'),
                 P(f'M{RX+13} 84 L{RX-12} 83 L{RX-12} 88 L{RX+13} 89 Z', 'hairShade')],
    'arched': [P(f'M{LX-12} 88 C{LX-6} 78 {LX+4} 78 {LX+12} 86', 'none', 'hairShade', 3), P(f'M{RX-12} 86 C{RX-4} 78 {RX+6} 78 {RX+12} 88', 'none', 'hairShade', 3)],
}
noses = {
    'button': [P('M96 116 C96 122 104 122 104 116', 'none', 'skinShade', 3)],
    'small': [P('M100 104 L96 118 C98 121 102 121 104 118', 'none', 'skinShade', 2.6)],
    'line': [P('M98 106 C96 112 96 116 101 118', 'none', 'skinShade', 2.6)],
}
facial = {
    'none': [],
    'stubble': [P('M58 124 C62 152 84 164 100 164 C116 164 138 152 142 124 C132 142 116 148 100 148 C84 148 68 142 58 124 Z', 'hairShade', None, 0, 0.3)],
    'mustache': [P('M82 128 C90 120 98 122 100 126 C102 122 110 120 118 128 C110 130 104 130 100 128 C96 130 90 130 82 128 Z', 'hair')],
    'beard': [P('M52 110 C54 150 80 170 100 170 C120 170 146 150 148 110 C140 130 128 142 114 140 C108 136 92 136 86 140 C72 142 60 130 52 110 Z', 'hair'),
              P('M84 128 C92 122 98 124 100 127 C102 124 108 122 116 128 C108 131 92 131 84 128 Z', 'hair')],
    'full': [P('M46 104 C46 152 76 176 100 176 C124 176 154 152 154 104 C148 126 136 140 118 140 C110 134 90 134 82 140 C64 140 52 126 46 104 Z', 'hair'),
             P('M82 128 C90 120 98 122 100 126 C102 122 110 120 118 128 C110 132 90 132 82 128 Z', 'hair')],
    'chevron': [P('M80 130 C88 120 98 122 100 125 C102 122 112 120 120 130 C112 128 104 129 100 130 C96 129 88 128 80 130 Z', 'hair')],
    'goatee': [P('M88 140 C90 156 110 156 112 140 C106 146 94 146 88 140 Z', 'hair'),
               P('M86 128 C92 123 98 124 100 127 C102 124 108 123 114 128', 'none', 'hair', 3)],
}
glasses = {
    'none': [],
    'round': [P(circle(LX, EY, 15), 'none', 'glasses', 3.2), P(circle(RX, EY, 15), 'none', 'glasses', 3.2), P(f'M{LX+15} {EY} C96 {EY-4} 104 {EY-4} {RX-15} {EY}', 'none', 'glasses', 3)],
    'square': [P(f'M{LX-16} {EY-11} h32 v22 h-32 Z', 'none', 'glasses', 3.2), P(f'M{RX-16} {EY-11} h32 v22 h-32 Z', 'none', 'glasses', 3.2), P(f'M{LX+16} {EY-2} L{RX-16} {EY-2}', 'none', 'glasses', 3)],
    'cateye': [P(f'M{LX-18} {EY-12} L{LX+14} {EY-8} C{LX+16} {EY+10} {LX-10} {EY+14} {LX-14} {EY} Z', 'none', 'glasses', 3.2),
               P(f'M{RX+18} {EY-12} L{RX-14} {EY-8} C{RX-16} {EY+10} {RX+10} {EY+14} {RX+14} {EY} Z', 'none', 'glasses', 3.2),
               P(f'M{LX+14} {EY-6} L{RX-14} {EY-6}', 'none', 'glasses', 3)],
}
earrings = {
    'none': [],
    'studs': [P(circle(44, 118, 3.4), 'accent'), P(circle(156, 118, 3.4), 'accent')],
    'hoops': [P(circle(44, 126, 8), 'none', 'accent', 2.6), P(circle(156, 126, 8), 'none', 'accent', 2.6)],
}
headwear = {
    'none': [],
    'beanie': [P('M40 84 C40 34 70 20 100 20 C130 20 160 34 160 84 Z', 'outfit'), P('M36 76 h128 v16 h-128 Z', 'outfitShade'), P(circle(100, 18, 10), 'outfitShade')],
    'cap': [P('M44 78 C44 38 70 26 100 26 C130 26 156 38 156 78 Z', 'outfit'), P('M40 78 C70 70 150 70 176 84 C150 90 70 88 40 84 Z', 'outfitShade'), P(circle(100, 28, 4), 'outfitShade')],
    'bow': [P('M112 38 C100 16 70 20 76 42 C80 58 102 50 112 44 Z', 'accent'), P('M112 38 C124 16 154 20 148 42 C144 58 122 50 112 44 Z', 'accent'), P(ellipse(112, 41, 7, 8), 'outfitShade')],
    'flowers': [P(''.join(f'{circle(x+dx, y+dy, 5.5)} ' for x, y in ((58, 50), (80, 36), (100, 32), (120, 36), (142, 50))
                             for dx, dy in ((0, -6), (6, 0), (0, 6), (-6, 0))), '#FFB3CC'),
                P(''.join(f'{circle(x, y, 4)} ' for x, y in ((58, 50), (80, 36), (100, 32), (120, 36), (142, 50))), '#FFD25C')],
}

# ------------------------------------------------------------------ expressions
def closed_happy():
    return [P(f'M{x-10} {EY+2} C{x-5} {EY-8} {x+5} {EY-8} {x+10} {EY+2}', 'none', 'ink', 3.4) for x in (LX, RX)]

def heart_eyes():
    return [P(heart(x, EY, 0.17), '#EA026A') for x in (LX, RX)]

def sunglasses():
    return [P(f'M{LX-20} {EY-12} L{LX+16} {EY-12} C{LX+16} {EY+12} {LX-14} {EY+16} {LX-20} {EY-12} Z', '#1E1A1C'),
            P(f'M{RX+20} {EY-12} L{RX-16} {EY-12} C{RX-16} {EY+12} {RX+14} {EY+16} {RX+20} {EY-12} Z', '#1E1A1C'),
            P(f'M{LX+16} {EY-10} L{RX-16} {EY-10}', 'none', '#1E1A1C', 4),
            P(f'M{LX-12} {EY-6} L{LX-4} {EY-6}', 'none', '#FFFFFF', 2.4, 0.6), P(f'M{RX-8} {EY-6} L{RX} {EY-6}', 'none', '#FFFFFF', 2.4, 0.6)]

def wink():
    return ([P(f'M{LX-10} {EY+1} C{LX-5} {EY+6} {LX+5} {EY+6} {LX+10} {EY+1}', 'none', 'ink', 3.4)] +
            [P(ellipse(RX, EY, 9, 10.5), 'white'), P(circle(RX, EY + 1, 6.4), 'eye'), P(circle(RX, EY + 1, 3.2), 'ink'),
             P(circle(RX + 2.2, EY - 1.6, 1.9), 'white'), P(f'M{RX-10} {EY-3} C{RX-5} {EY-11} {RX+5} {EY-11} {RX+10} {EY-3}', 'none', 'ink', 2.4)])

def wide():
    out = []
    for x in (LX, RX):
        out += [P(ellipse(x, EY, 10.5, 12.5), 'white'), P(circle(x, EY, 5), 'eye'), P(circle(x, EY, 2.6), 'ink'), P(circle(x + 2, EY - 2, 1.6), 'white'),
                P(f'M{x-11} {EY-4} C{x-5} {EY-14} {x+5} {EY-14} {x+11} {EY-4}', 'none', 'ink', 2.2)]
    return out

def sleepy():
    return [P(f'M{x-10} {EY+1} C{x-5} {EY+6} {x+5} {EY+6} {x+10} {EY+1}', 'none', 'ink', 3.2) for x in (LX, RX)]

mouths = {
    'smile': [P('M86 130 C92 140 108 140 114 130', 'none', 'ink', 3.2)],
    'grin': [P('M82 128 C84 146 116 146 118 128 Z', '#5A1E2E'), P('M86 129 L114 129 L112 134 L88 134 Z', '#FFFFFF'), P('M92 141 C96 137 104 137 108 141 C104 144 96 144 92 141 Z', '#FF8FA3')],
    'laugh': [P('M78 126 C80 152 120 152 122 126 Z', '#5A1E2E'), P('M82 127 L118 127 L116 133 L84 133 Z', '#FFFFFF'), P('M88 144 C94 138 106 138 112 144 C106 149 94 149 88 144 Z', '#FF8FA3')],
    'o': [P(ellipse(100, 136, 7, 9), '#5A1E2E')],
    'frown': [P('M88 140 C94 131 106 131 112 140', 'none', 'ink', 3.2)],
    'flat': [P('M88 134 L112 134', 'none', 'ink', 3.2)],
    'kiss': [P('M96 128 C104 128 106 134 100 136 C106 138 104 144 96 144', 'none', 'lip', 3.4)],
    'tongue': [P('M84 128 C88 142 112 142 116 128 Z', '#5A1E2E'), P('M94 134 C94 150 108 150 108 134 Z', '#FF7F97')],
    'lips': [P('M86 132 C92 128 97 130 100 131 C103 130 108 128 114 132 C108 140 92 140 86 132 Z', 'lip')],
}
blush = [P(circle(68, 122, 8), 'blush', None, 0, 0.45), P(circle(132, 122, 8), 'blush', None, 0, 0.45)]

tear = [P('M136 110 C132 118 132 124 136 126 C140 124 140 118 136 110 Z', '#8EC5F0')]
angry_brows = [P(f'M{LX-12} 82 L{LX+12} 90', 'none', 'hairShade', 4), P(f'M{RX+12} 82 L{RX-12} 90', 'none', 'hairShade', 4)]
sad_brows = [P(f'M{LX-12} 90 L{LX+10} 82', 'none', 'hairShade', 3.4), P(f'M{RX+12} 90 L{RX-10} 82', 'none', 'hairShade', 3.4)]

# poses: eyes, mouth, brows override, extras before/after, texts
def bubble(text, x=150, y=34, w=64):
    return {'shapes': [P(f'M{x-w/2} {y-18} h{w} a10 10 0 0 1 10 10 v16 a10 10 0 0 1 -10 10 h-{w-22} l-12 12 l2 -12 h-{2} a10 10 0 0 1 -10 -10 v-16 a10 10 0 0 1 10 -10 Z', '#FFFFFF', '#2A0A1A', 2.5)],
            'texts': [{'t': text, 'x': x + 5, 'y': y + 3, 'size': 17, 'fill': '#EA026A', 'font': 'Fredoka'}]}

poses = {
    'happy': {'eyes': None, 'mouth': 'smile', 'extra': []},
    'laugh': {'eyes': 'closed', 'mouth': 'laugh', 'extra': []},
    'wink': {'eyes': 'wink', 'mouth': 'tongue', 'extra': []},
    'love': {'eyes': 'heart', 'mouth': 'grin', 'extra': [P(heart(40, 40, 0.14), '#EA026A'), P(heart(166, 58, 0.1), '#FF5C9E'), P(heart(28, 76, 0.08), '#FF8DBB')]},
    'cool': {'eyes': 'sun', 'mouth': 'smile', 'extra': []},
    'wow': {'eyes': 'wide', 'mouth': 'o', 'extra': [], 'bubble': 'OMG'},
    'sad': {'eyes': None, 'mouth': 'frown', 'brows': 'sad', 'extra': tear},
    'angry': {'eyes': None, 'mouth': 'flat', 'brows': 'angry', 'extra': [P('M160 36 l6 -12 l6 12 l-6 -4 Z M172 50 l12 -6 l-4 12 l-2 -6 Z', '#E0354F')]},
    'kiss': {'eyes': 'closed', 'mouth': 'kiss', 'extra': [P(heart(146, 120, 0.12), '#EA026A')]},
    'sleepy': {'eyes': 'sleepy', 'mouth': 'flat', 'extra': [], 'texts': [{'t': 'z', 'x': 150, 'y': 58, 'size': 16, 'fill': '#7B4AE2', 'font': 'Fredoka'},
                                                                      {'t': 'Z', 'x': 162, 'y': 42, 'size': 22, 'fill': '#7B4AE2', 'font': 'Fredoka'}]},
    'hi': {'eyes': None, 'mouth': 'grin', 'extra': [], 'bubble': 'Hi!'},
    'lol': {'eyes': 'closed', 'mouth': 'laugh', 'extra': [], 'bubble': 'LOL'},
    'yay': {'eyes': 'closed', 'mouth': 'grin', 'extra': [P('M34 30 l4 10 l10 2 l-8 6 l2 10 l-8 -6 l-8 6 l2 -10 l-8 -6 l10 -2 Z', '#FFB547'),
                                                           P('M160 22 l3 7 l7 1 l-5 4 l1 7 l-6 -4 l-6 4 l1 -7 l-5 -4 l7 -1 Z', '#EA026A'),
                                                           P(circle(24, 70, 4), '#8EC5F0'), P(circle(176, 64, 4), '#A8E6B8')]},
    'bye': {'eyes': None, 'mouth': 'smile', 'extra': [], 'bubble': 'Bye!'},
}

# ------------------------------------------------------------------ dart output
def dstr(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace('$', '\\$') + "'"

def dpart(p):
    args = [dstr(p['d']), dstr(p['fill'])]
    if p['stroke']:
        args.append(f"stroke: {dstr(p['stroke'])}")
    if p['sw']:
        args.append(f"sw: {p['sw']}")
    if p['op'] != 1:
        args.append(f"op: {p['op']}")
    return f"AP({', '.join(args)})"

def dlist(parts):
    return '[' + ', '.join(dpart(p) for p in parts) + ']'

def dmap(name, m):
    lines = [f'const Map<String, List<AP>> {name} = {{']
    for k, v in m.items():
        lines.append(f"  {dstr(k)}: {dlist(v)},")
    lines.append('};')
    return '\n'.join(lines)

pose_eyes = {'closed': closed_happy(), 'heart': heart_eyes(), 'sun': sunglasses(), 'wink': wink(), 'wide': wide(), 'sleepy': sleepy()}
pose_brows = {'sad': sad_brows, 'angry': angry_brows}
bubbles = {}
pose_lines = ['const Map<String, APose> avatarPoses = {']
for k, v in poses.items():
    shapes = list(v['extra'])
    texts = list(v.get('texts', []))
    if v.get('bubble'):
        b = bubble(v['bubble'])
        shapes += b['shapes']
        texts += b['texts']
    tx = '[' + ', '.join(f"AT({dstr(t['t'])}, {t['x']}, {t['y']}, {t['size']}, {dstr(t['fill'])}, {dstr(t['font'])})" for t in texts) + ']'
    pose_lines.append(f"  {dstr(k)}: APose(eyes: {dstr(v['eyes']) if v['eyes'] else 'null'}, mouth: {dstr(v['mouth'])}, "
                      f"brows: {dstr(v['brows']) if v.get('brows') else 'null'}, extra: {dlist(shapes)}, texts: {tx}),")
pose_lines.append('};')

dart = ['// GENERATED by the avatar art script. Coordinates are in a 200 x 240 box.',
        '// ignore_for_file: prefer_single_quotes, lines_longer_than_80_chars', '',
        'class AP {',
        '  const AP(this.d, this.fill, {this.stroke, this.sw = 0, this.op = 1});',
        '  final String d;', '  final String fill;', '  final String? stroke;', '  final double sw;', '  final double op;', '}', '',
        'class AT {', '  const AT(this.text, this.x, this.y, this.size, this.fill, this.font);',
        '  final String text;', '  final double x;', '  final double y;', '  final double size;', '  final String fill;', '  final String font;', '}', '',
        'class APose {', '  const APose({this.eyes, required this.mouth, this.brows, this.extra = const [], this.texts = const []});',
        '  final String? eyes;', '  final String mouth;', '  final String? brows;', '  final List<AP> extra;', '  final List<AT> texts;', '}', '',
        f'const List<AP> avatarNeck = {dlist(neck)};', f'const List<AP> avatarEars = {dlist(ears)};', f'const List<AP> avatarBlush = {dlist(blush)};',
        dmap('avatarBodies', body), dmap('avatarHeads', {k: [P(v, 'skin')] for k, v in heads.items()}),
        dmap('avatarHairBack', hair_back), dmap('avatarHairFront', hair_front), dmap('avatarHairFrame', hair_face_cut),
        dmap('avatarEyes', eyes), dmap('avatarPoseEyes', pose_eyes), dmap('avatarBrows', brows), dmap('avatarPoseBrows', pose_brows),
        dmap('avatarNoses', noses), dmap('avatarMouths', mouths), dmap('avatarFacialHair', facial), dmap('avatarGlasses', glasses),
        dmap('avatarEarrings', earrings), dmap('avatarHeadwear', headwear), '\n'.join(pose_lines)]
os.makedirs(os.path.join(APP, 'lib/avatar'), exist_ok=True)
open(os.path.join(APP, 'lib/avatar/avatar_parts.dart'), 'w').write('\n\n'.join(dart) + '\n')

# ------------------------------------------------------------------ preview
if PREVIEW:
    from playwright.sync_api import sync_playwright
    def shade(hexc, f):
        h = hexc.lstrip('#'); r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        return '#%02x%02x%02x' % (int(r*f), int(g*f), int(b*f))
    def svg(cfg, pose):
        roles = {'skin': cfg['skin'], 'skinShade': shade(cfg['skin'], 0.86), 'hair': cfg['hair'], 'hairShade': shade(cfg['hair'], 0.72),
                 'eye': cfg['eye'], 'lip': cfg.get('lip', '#D9637A'), 'outfit': cfg['outfit'], 'outfitShade': shade(cfg['outfit'], 0.8),
                 'blush': '#FF7A9A', 'ink': '#2A0A1A', 'white': '#FFFFFF', 'glasses': '#2A0A1A', 'accent': cfg.get('accent', '#FFB547'), 'none': 'none'}
        col = lambda c: roles.get(c, c) if c else 'none'
        pz = poses[pose]
        layers = []
        layers += hair_back.get(cfg['hairStyle'], [])
        layers += neck + body[cfg['outfitStyle']] + ears
        layers += [P(heads[cfg['face']], 'skin')]
        layers += blush
        layers += pose_brows.get(pz.get('brows'), brows[cfg['brows']]) if pz.get('brows') else brows[cfg['brows']]
        layers += pose_eyes[pz['eyes']] if pz['eyes'] else eyes[cfg['eyes']]
        layers += noses[cfg['nose']]
        layers += mouths[pz['mouth'] if not (pz['mouth'] == 'smile' and cfg.get('lipstick')) else 'lips']
        layers += facial[cfg['facial']]
        layers += hair_face_cut.get(cfg['hairStyle'], [])
        layers += hair_front[cfg['hairStyle']]
        layers += earrings[cfg['earrings']]
        layers += headwear[cfg['hat']]
        if pz['eyes'] != 'sun':
            layers += glasses[cfg['glasses']]
        extra = list(pz['extra']); texts = list(pz.get('texts', []))
        if pz.get('bubble'):
            b = bubble(pz['bubble']); extra += b['shapes']; texts += b['texts']
        layers += extra
        body_s = ''.join(f'<path d="{p["d"]}" fill="{col(p["fill"])}" stroke="{col(p["stroke"])}" stroke-width="{p["sw"]}" '
                         f'opacity="{p["op"]}" stroke-linecap="round" stroke-linejoin="round" fill-rule="nonzero"/>' for p in layers)
        body_s += ''.join(f'<text x="{t["x"]}" y="{t["y"]}" text-anchor="middle" font-family="sans-serif" font-weight="700" font-size="{t["size"]}" fill="{t["fill"]}">{t["t"]}</text>' for t in texts)
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 240" width="200" height="240">{body_s}</svg>'
    cfgs = [
        dict(skin='#F2C9A9', hair='#2B1B14', eye='#5B3A29', outfit='#EA026A', face='oval', hairStyle='long', brows='soft', eyes='lashes', nose='small', facial='none', glasses='none', earrings='hoops', hat='none', outfitStyle='tee', lipstick=True),
        dict(skin='#8D5A3B', hair='#1A1110', eye='#3B2416', outfit='#3A7BD5', face='square', hairStyle='short', brows='thick', eyes='round', nose='button', facial='beard', glasses='square', earrings='none', hat='none', outfitStyle='hoodie'),
        dict(skin='#E8B48E', hair='#C98A3E', eye='#3A7BD5', outfit='#9DB89A', face='heart', hairStyle='wavy', brows='arched', eyes='almond', nose='line', facial='none', glasses='round', earrings='studs', hat='bow', outfitStyle='dress', accent='#EA026A'),
        dict(skin='#C68863', hair='#111111', eye='#2B1B14', outfit='#B892FF', face='round', hairStyle='hijab', brows='soft', eyes='lashes', nose='small', facial='none', glasses='none', earrings='none', hat='none', outfitStyle='turtleneck'),
        dict(skin='#F7D7C4', hair='#E06A8C', eye='#2EC4A6', outfit='#FFB547', face='oval', hairStyle='bun', brows='soft', eyes='round', nose='button', facial='none', glasses='cateye', earrings='studs', hat='none', outfitStyle='shirt'),
        dict(skin='#5C3A28', hair='#1A1110', eye='#2B1B14', outfit='#2EC4A6', face='round', hairStyle='afro', brows='thick', eyes='round', nose='button', facial='goatee', glasses='none', earrings='none', hat='none', outfitStyle='tee'),
    ]
    cfgs.append(dict(skin='#E8B48E', hair='#2B1B14', eye='#5B3A29', outfit='#222222', face='jaw', hairStyle='quiff', brows='straight', eyes='round', nose='small', facial='stubble', glasses='none', earrings='none', hat='none', outfitStyle='suit', accent='#EA026A'))
    cfgs.append(dict(skin='#C68863', hair='#111111', eye='#2B1B14', outfit='#3A7BD5', face='jaw', hairStyle='fade', brows='thick', eyes='almond', nose='line', facial='full', glasses='none', earrings='none', hat='none', outfitStyle='jacket'))
    cfgs.append(dict(skin='#F2C9A9', hair='#7A4B2A', eye='#3A7BD5', outfit='#2EC4A6', face='oval', hairStyle='spiky', brows='straight', eyes='round', nose='button', facial='none', glasses='round', earrings='none', hat='none', outfitStyle='polo'))
    cfgs.append(dict(skin='#A86F4C', hair='#111111', eye='#2B1B14', outfit='#F7E3C8', face='square', hairStyle='manbun', brows='thick', eyes='round', nose='small', facial='chevron', glasses='none', earrings='none', hat='none', outfitStyle='kurta', accent='#FFB547'))
    cfgs.append(dict(skin='#FBE3D3', hair='#E8C07A', eye='#6E9F6A', outfit='#B892FF', face='round', hairStyle='fringe', brows='soft', eyes='round', nose='button', facial='none', glasses='square', earrings='none', hat='none', outfitStyle='hoodie'))
    cfgs.append(dict(skin='#8D5A3B', hair='#1A1110', eye='#2B1B14', outfit='#E0354F', face='jaw', hairStyle='slick', brows='straight', eyes='almond', nose='line', facial='goatee', glasses='none', earrings='studs', hat='none', outfitStyle='tee', accent='#D9D9D9'))
    cells = []
    for i, c in enumerate(cfgs):
        for pose in (['happy'] if i else list(poses.keys())):
            cells.append(svg(c, pose))
    for hs in hair_front:
        c = dict(cfgs[0]); c['hairStyle'] = hs; c['lipstick'] = False
        cells.append(svg(c, 'happy'))
    for hw in headwear:
        c = dict(cfgs[1]); c['hat'] = hw
        cells.append(svg(c, 'happy'))
    html = '<html><body style="margin:0;background:#FFE3EF;display:flex;flex-wrap:wrap;width:1600px">' + ''.join(f'<div style="margin:4px">{s}</div>' for s in cells) + '</body></html>'
    with sync_playwright() as pw:
        b = pw.chromium.launch(); pg = b.new_page(viewport={'width': 1600, 'height': 900})
        pg.set_content(html); pg.screenshot(path=PREVIEW, full_page=True); b.close()
print('ok')

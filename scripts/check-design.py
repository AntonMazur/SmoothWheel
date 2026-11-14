"""Validate semantic text contrast and shared CSS/Swift token generation."""
import json
from pathlib import Path
import subprocess
import sys
root=Path(__file__).resolve().parents[1]
tokens=json.loads((root/'design/tokens/soft-form.json').read_text())
def luminance(value):
    rgb=[int(value[i:i+2],16)/255 for i in (1,3,5)]
    rgb=[x/12.92 if x<=0.04045 else ((x+.055)/1.055)**2.4 for x in rgb]
    return sum(x*y for x,y in zip(rgb,[.2126,.7152,.0722]))
for theme,colors in tokens['color'].items():
    assert set(colors)==set(tokens['color']['light'])
    for text,background,minimum in [('text','paper',4.5),('textMuted','paper',4.5),('text','surface',4.5),
                                    ('textMuted','surface',4.5),('accentText','paper',4.5),
                                    ('accentDisplay','paper',3),('onPrimary','primary',4.5),('onPrimary','primaryHover',4.5)]:
        low,high=sorted([luminance(colors[text]),luminance(colors[background])])
        contrast=(high+.05)/(low+.05)
        assert contrast>=minimum, f'{theme}: {text}/{background} contrast {contrast:.2f} < {minimum}'
subprocess.run([sys.executable,str(root/'scripts/generate-design-tokens.py'),'--check'],check=True)
print('Semantic text contrast passes for light and dark appearances.')

# Fonts

Hanken Grotesk and Martian Mono, both under the SIL Open Font License 1.1 (`OFL.txt` in each folder).

Taken from the google/fonts repository (`ofl/hankengrotesk/HankenGrotesk[wght].ttf`,
`ofl/martianmono/MartianMono[wdth,wght].ttf`) and cut into one static file per weight, because Qt picks weights
from separate files but not from a variable font's named instances:

    fonttools varLib.instancer 'HankenGrotesk[wght].ttf' wght=600 --update-name-table --static -o HankenGrotesk-SemiBold.ttf
    fonttools varLib.instancer 'MartianMono[wdth,wght].ttf' wght=600 wdth=100 --update-name-table --static -o MartianMono-SemiBold.ttf

Hanken Grotesk: ExtraLight 200 to Bold 700. Martian Mono: normal width (100), Regular 400 to Bold 700.
`core/Theme.qml` loads every file with a `FontLoader`.

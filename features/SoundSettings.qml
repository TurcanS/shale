import QtQuick
import QtQuick.Layouts
import "../core"
import "../components" as C

// Settings → Sound: volume limits, the player's time and the equalizer.
ColumnLayout {
    spacing: 8
    C.Group {
        C.SettingToggle {
            text: "Allow volume amplification up to 150%"
            description: "Volume sliders go past 100%"
            key: "amplification"
        }
        C.SettingToggle {
            text: "Show time left instead of track length"
            description: "On the Player"
            key: "mediaRemaining"
        }
        C.OpenRow {
            label: "Equalizer"
            description: "Curves for the output, in Control → Sound"
            action: "Open the equalizer"
            glyph: "equalizer"
            onOpened: {
                ShellState.open("control");
                ShellState.detail = "audio";
            }
        }
    }
}

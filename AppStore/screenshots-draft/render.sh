#!/usr/bin/env bash
# Draft App Store screenshots from the instrument itself, rendered on Linux (or macOS) through
# SundialSVG and headless Chrome. They are stand-ins: CI's simulator screenshots (the
# SundialUITests target, uploaded by .github/workflows/apple.yml) replace them. See README.md.
#
#   AppStore/screenshots-draft/render.sh            # from anywhere; needs Swift and Chrome
#
# The scenes are the Play listing's (sundial-android-native/play/graphics and StoreAssetsCapture /
# WatchStoreCapture there), frozen at the moment the UI tests use.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
package="$(cd "$here/../.." && pwd)"
cd "$package"

# Friday 25 September 2026, 8:30 pm in Los Angeles: the moment every store screenshot shows.
instant="2026-09-25T20:30"
zone="America/Los_Angeles"
# The Android store captures' sample reader: an Aries born 18 April 1990, and their reading.
birth="1990-04-18"
reading="The brass gears of the heavens turn in your favour today, Aries. With the Sun in Libra across from your own sign, partnerships ask for patience and a generous ear. The Moon brightens your curiosity; follow a question you have been saving. Venus lends grace to a difficult conversation, and by evening a small kindness returns to you twice over."

swift build -c release --product sundial-render >/dev/null
render="$(swift build -c release --show-bin-path)/sundial-render"

# shot NAME LAYOUT WIDTH HEIGHT DENSITY VIEW STYLE astrology|astronomy [extra sundial-render flags]
shot() {
    local name="$1" layout="$2" width="$3" height="$4" density="$5" view="$6" style="$7" zodiac="$8"
    shift 8
    local flags=(--layout "$layout" --width "$width" --height "$height" --density "$density"
                 --view "$view" --style "$style" --instant "$instant" --zone "$zone"
                 --assets "$package/Assets" --png "$here/$name.png")
    if [[ "$zodiac" == astrology ]]; then
        flags+=(--astrology --birth-date "$birth")
        # Phones and tablets show the day's reading in the horoscope cards; the watch has none.
        [[ "$layout" == phone ]] && flags+=(--horoscope "$reading")
    fi
    "$render" "${flags[@]}" "$@" >/dev/null
    echo "$name.png"
}

# iPhone 6.9" (iPhone 17 Pro Max class): 1320 × 2868 px, 440 × 956 pt at 3×. The Play phone set.
shot iPhone-6.9-1-solar-view         phone 1320 2868 3 helio    crimsonNebula astronomy
shot iPhone-6.9-2-earth-view         phone 1320 2868 3 earth    crimsonNebula astronomy
shot iPhone-6.9-3-brass-astrology    phone 1320 2868 3 helio    brassWatch    astrology
shot iPhone-6.9-4-brass-earth-view   phone 1320 2868 3 earth    brassWatch    astronomy
shot iPhone-6.9-5-galactic           phone 1320 2868 3 galactic deepSpaceBlue astronomy

# iPad 13" (iPad Pro 13-inch): 2064 × 2752 px portrait, 1032 × 1376 pt at 2×. The Play tablet set
# (its fourth shot, the astrology menu, is app UI and only comes from the simulator).
shot iPad-13-1-brass-astrology       phone 2064 2752 2 helio    brassWatch    astrology
shot iPad-13-2-earth-view            phone 2064 2752 2 earth    crimsonNebula astronomy
shot iPad-13-3-solar-view            phone 2064 2752 2 helio    deepSpaceBlue astronomy
# The same in landscape (2752 × 2064), as the Play tablet screenshots show Sundial.
shot iPad-13-landscape-1-brass-astrology  phone 2752 2064 2 helio  brassWatch    astrology
shot iPad-13-landscape-2-earth-view       phone 2752 2064 2 earth  crimsonNebula astronomy
shot iPad-13-landscape-3-solar-view       phone 2752 2064 2 helio  deepSpaceBlue astronomy

# Apple Watch Ultra 3 (49 mm): 422 × 514 px, 211 × 257 pt at 2×, the rectangular watch layout. The
# Wear OS set. Only the first shows the clock, as the watch app starts: an Apple Watch listing must
# not look like a watch face (App Review 4.2.4), so the rest show the instrument alone
# (-screenshotClock off in .github/workflows/apple.yml).
shot Watch-Ultra-1-brass-astrology   watchRect 422 514 2 helio    brassWatch    astrology --clock
shot Watch-Ultra-2-brass-earth-view  watchRect 422 514 2 earth    brassWatch    astronomy
shot Watch-Ultra-3-solar-view        watchRect 422 514 2 helio    crimsonNebula astronomy
shot Watch-Ultra-4-earth-view        watchRect 422 514 2 earth    deepSpaceBlue astronomy
shot Watch-Ultra-5-galactic          watchRect 422 514 2 galactic cosmicViolet  astronomy

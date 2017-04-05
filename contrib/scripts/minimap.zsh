#!/usr/bin/env zsh

cd $1
shift

scale="${1-20}%"
shift

vp=($*)

# Note: -draw handles out-of-bound coordinates
draw=(
    -fill none -stroke red -draw "rectangle $vp[1],-2 $vp[2],800"
    )


# set -x
convert '*.png' -scale $scale +append $draw minimap.png
set +x


pkill feh
feh --title "*feh-minimap*" minimap.png &


function scale {
    convert '*.png' -scale $scale 'thumb-%02d.png'
}

function compose {
    convert +append thumb*.png minimap.png
}

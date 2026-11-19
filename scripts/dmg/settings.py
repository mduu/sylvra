# dmgbuild settings for Sylvra's installer window (paths come in via -D).
# Layout must match scripts/dmg/make-background.swift: 660×430 points, icons at (165, 180) and (495, 180).
import os.path

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("volume_icon")  # noqa: F821
background = defines["background"]  # noqa: F821

default_view = "icon-view"
window_rect = ((200, 120), (660, 458))  # 430 points of content + title bar
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {app_name: (165, 180), "Applications": (495, 180)}

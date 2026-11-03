"""Write the Lexisle Finder layout directly, without Finder or AppleScript automation."""

import os
import subprocess

app = os.path.abspath(defines["app"])
app_name = defines["name"]
app_filename = os.path.basename(app)
if app_filename != app_name + ".app":
    raise ValueError("The application bundle name does not match the configured product name")

files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
default_view = "icon-view"
window_rect = ((180, 140), (680, 520))
icon_locations = {app_filename: (180, 250), "Applications": (500, 250)}
icon_size = 104
text_size = 13
label_pos = "bottom"
arrange_by = None

# Changing the app bundle's FinderInfo after signing can invalidate its resource seal.
hide_extensions = []
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_item_info = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False


def create_hook(mount_point, options):
    """Reject a damaged app copy before converting the writable image to UDZO."""
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--strict", os.path.join(mount_point, app_filename)],
        check=True,
    )

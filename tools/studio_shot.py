# Captures a window from its own offscreen pixmap (X Composite), so windows
# on top of it do not show up. Never raises or focuses it. Used by studio_shot.sh.
import sys
from Xlib import display, X
from Xlib.ext import composite
from PIL import Image
d = display.Display()
root = d.screen().root
w = d.create_resource_object("window", int(sys.argv[1]))
while True:  # climb to the top-level frame (a direct child of root)
    p = w.query_tree().parent
    if p.id == root.id:
        break
    w = p
w.composite_redirect_window(composite.RedirectAutomatic)
d.sync()
g = w.get_geometry()
pm = w.composite_name_window_pixmap()
raw = pm.get_image(0, 0, g.width, g.height, X.ZPixmap, 0xFFFFFFFF)
Image.frombytes("RGB", (g.width, g.height), raw.data, "raw", "BGRX").save(sys.argv[2])

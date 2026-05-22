# Running Tests
#
# Tests use the GUT (Godot Unit Test) framework.
# https://github.com/bitwes/Gut
#
# ## Setup
#
# 1. Open the project in the Godot 4 editor.
# 2. Go to AssetLib and search for "GUT".
# 3. Install the GUT addon and enable it in Project → Project Settings → Plugins.
#
# Alternatively, clone GUT directly:
#
#   cd <project_root>
#   git clone https://github.com/bitwes/Gut.git addons/gut
#
# ## Running
#
# From the Godot editor: open the GUT panel (bottom dock) and click Run All.
#
# From the command line (headless):
#
#   godot --headless -s addons/gut/gut_cmdln.gd \
#     -gdir=res://tests/unit \
#     -gprefix=test_ \
#     -gsuffix=.gd \
#     -gexit
#
# ## Test locations
#
#   tests/unit/test_mouse_look_tracker.gd   — MouseLookTracker (issue #2)
#   tests/unit/test_udp_control_output.gd  — UDPControlOutput  (issue #3)
#   tests/unit/test_opentrack_udp_tracker.gd — OpenTrackUDPTracker (issue #5)
#   tests/unit/test_local_file_source.gd   — LocalFileSource   (issue #4)

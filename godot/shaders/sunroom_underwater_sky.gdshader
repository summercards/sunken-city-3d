shader_type sky;
#include "res://shaders/sunroom_underwater_color.gdshaderinc"
void sky() { COLOR=uw_display_to_hdr(region_water_display(EYEDIR)); }

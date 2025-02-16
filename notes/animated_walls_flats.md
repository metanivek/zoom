Animated Walls and Flats

Docs:
https://doomwiki.org/wiki/Animated_flat
https://doomwiki.org/wiki/Animated_wall


Original code
https://github.com/id-Software/DOOM/blob/a77dfb96cb91780ca334d0d4cfd86957558007e0/linuxdoom-1.10/p_spec.c

I think all the specs with istexture = true are walls.

```
//
//      source animation definition
//
typedef struct
{
    boolean	istexture;	// if false, it is a flat
    char	endname[9];
    char	startname[9];
    int		speed;
} animdef_t;


// Floor/ceiling animation sequences,
//  defined by first and last frame,
//  i.e. the flat (64x64 tile) name to
//  be used.
// The full animation sequence is given
//  using all the flats between the start
//  and end entry, in the order found in
//  the WAD file.
//
animdef_t		animdefs[] =
{
    {false,	"NUKAGE3",	"NUKAGE1",	8},
    {false,	"FWATER4",	"FWATER1",	8},
    {false,	"SWATER4",	"SWATER1", 	8},
    {false,	"LAVA4",	"LAVA1",	8},
    {false,	"BLOOD3",	"BLOOD1",	8},

    // DOOM II flat animations.
    {false,	"RROCK08",	"RROCK05",	8},		
    {false,	"SLIME04",	"SLIME01",	8},
    {false,	"SLIME08",	"SLIME05",	8},
    {false,	"SLIME12",	"SLIME09",	8},

    {true,	"BLODGR4",	"BLODGR1",	8},
    {true,	"SLADRIP3",	"SLADRIP1",	8},

    {true,	"BLODRIP4",	"BLODRIP1",	8},
    {true,	"FIREWALL",	"FIREWALA",	8},
    {true,	"GSTFONT3",	"GSTFONT1",	8},
    {true,	"FIRELAVA",	"FIRELAV3",	8},
    {true,	"FIREMAG3",	"FIREMAG1",	8},
    {true,	"FIREBLU2",	"FIREBLU1",	8},
    {true,	"ROCKRED3",	"ROCKRED1",	8},

    {true,	"BFALL4",	"BFALL1",	8},
    {true,	"SFALL4",	"SFALL1",	8},
    {true,	"WFALL4",	"WFALL1",	8},
    {true,	"DBRAIN4",	"DBRAIN1",	8},
	
    {-1}
};
```
# Goal
The goal of this plugin is to give me the artist a cleaner user interface to a very complex runtime terrain generation system I've built.
Right now this runtime terrain generation system is hardcoded with a lot of values spread out across the system. What we are hoping to achieve here is make a plugin that distils all these properties and values into a cohesive, easy to use, meaningful tool that allows me to craft unique and interesting terrains for games without having to remember lots of hardcoded values across lots of scripts.

In the future if this works well and is found to have beneifit, it will be turned into a public plugin for others to use. Further more the plugin we are building will work in conjunction with our core terrain generating code at runtime, but eventually will have a full buildtime feature too.

For more information about the core runtime terrain generating scripts, see (Core-Terrain-Generator-Scripts Readme)[https://github.com/drolsen/TerraLux/blob/main/Core-Terrain-Generator-Scripts.md]

# TerraLux Plugin User Flow

1) User opens plugin and is ready to make their first biome.
2) User makes biome, selects from exsisting or loads up previously editing biome and is put into the "Biome Edit Mode".
3) User alters and tweaks their Biome properties until perfected, and then user moves onto "Materials Edit Mode"
4) User alters and tweaks their Materials properties until perfected, and then moves onto "Environmental Edit Mode"
5) User alters and tweaks their Environmental properties until perfected, and then moves onto "Stamp Edit Mode"
6) User alters and tweaks their Stamp properties until perfected, and then moves onto "Lighting Edit Mode"
7) User alters and tweaks their Lighting properties until perfectd, and then moves onto "Cave Edit Mode"
8) User alters and tweaks their Cave properties until perfected and then has a completed all plugin options.


# TerraLux Plugin Specs

First lets start with the high level UI overview.
This shows all the primary areas of our plugin:

![layout of our plugin](https://github.com/drolsen/terralux/blob/main/comps/Plugin-Layout.jpg?raw=true)

- Main toolbar = Where we define our biomes to start working on terrains as well as switch between different edit modes.
- Properties Window = Is where each edit mode's available properties are presented to use to tweak and fine tune.
- Preview Window = Is where we get to preview the changes of our properties across all our different edit modes. 

Simple requirements here:
- When resizing the window, the properties frame remains a fixed X size, but can resize in Y.
- When resizing the window, the preview window can resize in both X and Y
- When resizing the window, the main toolbar remains a fixed Y size, but can resize in the X.

---
## First Time Opening Plugin
This is our view of our plugin the very first time being opened never having opened the plugin up before:
![first time opening plugin](https://github.com/drolsen/terralux/blob/main/comps/First-Time-Plugin-Open.jpg?raw=true)

Lets break down this first comp:
- Main tool bar has a drop down that is empty, a plus button and a series of disabled buttons. Buttons are disabled cause we have not defined our first biome yet.
- Properties window has nothing listed in it because no biome is defined yet / selected. However window is primed with a vertical scrollbar for when there will be properties eventually.
- Preview has nothing to preview yet because we have no defined / selected biome yet. It does however have a persistent logo of our plugin in the background until it eventually gets covered up once we have actual biome / terrains to preview.

Its expected from here that the user must make their first biome before they are able to jump into any of the editing modes for their biome and terrain.
![creating first biome](https://github.com/drolsen/terralux/blob/main/comps/First-Time-Making-Biome.jpg?raw=true)<br/>

Lets go over our Main Toolbar features now.

## Main Toolbar

### Biome Dropdown / Listing

Dropdown = This is where we will list all the unique biomes the user has made, they can switch between these biomes and see their complete list with this dropdown. <br/>
![biome dropdown empty state](https://github.com/drolsen/terralux/blob/main/screenshots/Bome-Dropdown-Empty-State.jpg?raw=true)

Plus Button = When clicked, the dropdown will be turned into a text field and the plus button replaced with a [OK] / [Cancel] confirmation buttons. User provides a unique name (no duplicate names) for their biome and clicks ok to make their first biome. Click cancel and they will jump out of the "make new biome" experience.  <br/>
![biome dropdown plus button](https://github.com/drolsen/terralux/blob/main/screenshots/Biome-Dropdown-Curate-State.jpg?raw=true)

Clicking Ok and Cancel makes the dropdown and plus button comes back; only clicking ok adds new biome to dropdown as an item and auto selects it for the user. 
When making a new biome, user should be put into the "Biome "edit mode automatically (more on what Biome edit mode is soon). <br/>
![biome dropdown closed state](https://github.com/drolsen/terralux/blob/main/screenshots/Biome-Dropdown-Closed-State.jpg?raw=true)

Clicking on this drop down will open it and allow the user to choose between may other possible Biomes they have made in the past. <br/>
![biome dropdown open state](https://github.com/drolsen/terralux/blob/main/screenshots/Biome-Dropdown-Open-State.jpg?raw=true)

### Edit Modes
All our next buttons are disabled until the user has made at least 1 biome: <br/>
![disabled buttons](https://github.com/drolsen/terralux/blob/main/screenshots/Toolbar-Disabled-Buttons.jpg?raw=true) <br/>
However once we do have at least one biome, these buttons are available to clicked with default an active states. 

Lets go over each of these buttons:

![default state](https://github.com/drolsen/terralux/blob/main/screenshots/World-Settings-Button.jpg?raw=true)
![active state](https://github.com/drolsen/terralux/blob/main/screenshots/World-Settings-Button-Active.jpg?raw=true) <br/>
- World Settings = Its disabled until user has at least 1 biome created / selected. Once available and clicked, a grouping of global properties shows up in our properties window (always the top) and button remains in a clicked state. Click it again and global properties grouping goes away in properties window.

![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Biome-Edit-Button.jpg?raw=true)
![active state](https://github.com/drolsen/terralux/blob/main/screenshots/Biome-Edit-Button-Active.jpg?raw=true) <br/>
- Biome Edit = Its disabled until user has at least 1 biome created / selected. Once available and clicked we move into the Biome edit mode which populates our properties window with all biome settings and brings up our preview window for this edit mode. This button should have a active state, but can't be clicked to turn off its active state. You can only see it not in a active state when you click another edit mode.

![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Materials-Edit-Button.jpg?raw=true)
![active state](https://github.com/drolsen/terralux/blob/main/screenshots/Materials-Edit-Button-Active.jpg?raw=true) <br/>
- Materials Edit = Its disabled until user has at least 1 biome created / selected. Once available and clicked we move into the Materials edit mode which populates our properties window with all material settings and brings up our preview window for this edit mode. This button should have a active state, but can't be clicked to turn off its active state. You can only see it not in a active state when you click another edit mode.

![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Environmental-Edit-Button.jpg?raw=true)
![active state](https://github.com/drolsen/terralux/blob/main/screenshots/Environmental-Edit-Button-Active.jpg?raw=true) <br/>
- Environmental Edit = This is our Environmental settings for defining all thins like trees, rocks, boulders, vegetation (is called vegetation in our code but soon will be called environmental in code) that will be scatted across our terrain, and how they are scattered.  Once available and clicked we move into the Environmental edit mode, which populates our properties window with all environment settings and brings up our preview window for this edit mode. This button should have a active state, but can't be clicked to turn off its active state. You can only see it not in a active state when you click another edit mode.

![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Stamp-Edit-Button.jpg?raw=true)
![active state](https://github.com/drolsen/terralux/blob/main/screenshots/Stamp-Edit-Button-Active.jpg?raw=true) <br/>
- Stamp Edit = This is our Stamp settings for defining model parts that will be stamped into the terrain to breakup repeated surfaces. This is done by calculating the volume of parts and using a fill on that volume of terrain after part has been place on the terrain like an Environmental. Once available and clicked we move into the Stamp edit mode, which populates our properties window with all stamp settings and brings up our preview window for this edit mode. This button should have a active state, but can't be clicked to turn off its active state. You can only see it not in a active state when you click another edit mode.

![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Lighting-Edit-Button.jpg?raw=true)
![active state](https://github.com/drolsen/terralux/blob/main/screenshots/Lighting-Edit-Button-Active.jpg?raw=true) <br/>
- Lighting Edit = This is our Lighting and atmosphere settings for defining camera fog color, offset and density as well as a day / night system.  Once available and clicked we move into the Lighting edit mode, which populates our properties window with all environment settings and brings up our preview window for this edit mode. This button should have a active state, but can't be clicked to turn off its active state. You can only see it not in a active state when you click another edit mode.

![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Cave-Edit-Button.jpg?raw=true)
![active state](https://github.com/drolsen/terralux/blob/main/screenshots/Cave-Edit-Button-Active.jpg?raw=true) <br/>
- Cave button = This is our Cave settings for defining sub terrain cave systems.  Once available and clicked we move into the Cave edit mode, which populates our properties window with all cave settings and brings up our preview window for this edit mode. This button should have a active state, but can't be clicked to turn off its active state. You can only see it not in a active state when you click another edit mode.

Next, we will move onto our properties requirements.

---

## Properties Window
The properties within this window across each of the above mentinoed edit modes, change from mode to mode. 
Its expected that as the user changes properties, the preview window will auto update with new changes (more on the preview window soon).

### Properties Window Cards
![anatomy of properties window card](https://github.com/drolsen/terralux/blob/main/screenshots/Properties-Card-Anatomy.jpg?raw=true) <br/>
A basic card anatomy is a header with a heading, expand collapse toggle in the header and of course the actual properties. 
The properties listed in a card are made up of a label on the left, and a field on the right. Please note however, not all properties listings will have a single field, some have up to three.
Some of the fields we will support in a properties listing are number inputs, float inputs, checkboxes and color pickers. All these fields should be native studio fields, never custom ones.

### Properties Window Card Sub Listings
There are also sub listings within cards, some of these sub listings are a basic listing: <br/>
![anatomy of properties window sublist card](https://github.com/drolsen/terralux/blob/main/screenshots/Properties-Sublisting-Anatomy.jpg?raw=true)

While other sub listings are user curated: <br/>
![anatomy of properties window sublist card](https://github.com/drolsen/terralux/blob/main/screenshots/Properties-Curated-Sublisting-Anatomy.jpg?raw=true)


## Edit Mode Properties

### Biome Edit Mode Properties

![biome edit mode properties](https://github.com/drolsen/terralux/blob/main/screenshots/Biome-Edit-Properties.jpg?raw=true)

- Altitude Properties Card
- Fractals Properties Card
- Ridges Properties Card
- Warping Properties Card
- Crevasses Properties Card
- Terraces Properties Card

Each of these cards have a card heading with a title and a expand/collapse up/down arrow.
Each property has a divider line, left aligned label and a right aligned field(s). Some properties have multiple fields for things like 2d vectors or Small / Medium / Large variants that have accompanying labels. <br/>

Lets go over each of the properties in each of the cards.
#### Altitude
- Max Altitude = float number input
- Elevation Trend = float number input

#### Fractals
- Amplitude = three float number inputs; one for small (S), one for medium (M) and one for large (L)
- Frequency = three float number inputs; one for small (S), one for medium (M) and one for large (L)

#### Ridges
- Amplitude = three float number inputs; one for small (S), one for medium (M) and one for large (L)
 Frequency = three float number inputs; one for small (S), one for medium (M) and one for large (L)

#### Warping
- Amplitude = two float number inputs; one for small (S), and one for large (L)
- Frequency = two float number inputs; one for small (S), and one for large (L)

#### Crevasses
- Depth Amplitude = single float number input
- Direction = two float number input; one for X and one for Y
- Sharp Exponent = single float number input
- Space Frequency = single float number input

#### Terraces
- Sharp Exponent = single float number input
- Space Frequency = single float number input

----
## Materials Edit Mode Properties
![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Materials-Edit-Properties.jpg?raw=true) <br/>
- 21 properties cards for each of the allowed terrain materials in roblox. 

(Roblox's permitted terrain materials)
- Asphalt
- Basalt
- Brick
- Cobblestone
- Concrete
- CrackedLava
- Glacier
- Grass
- Ground
- Ice
- LeafyGrass
- Limestone
- Mud
- Pavement
- Rock
- Salt
- Sand
- Sandstone
- Slate
- Snow
- WoodPlanks

Each card has a heading with title of that terrain material name, and a expand/collapse up/down arrow. (now we understand why properties window had a scrollbar primed this whole time).
Lets go over each of the properties in each of the cards:

### Material preview 
is just a normal preview of the available terrain material for a visual representation.
- Apply = checkbox which applies this material to our terrain (on / off switch if you will)
- Layer = number input. Zero is as low of a number you can set on this and zero denotes that its the terrains base material.
- Color = Studio color picker that will define that material's color for finer tuning that artist like. This really is just a middle man setting to what you find in workspace->terrain->materials already.

### Material Filters 
In the event that the material is not layer 0 (base material), users can add as many of what are called "filters" and define at what altitude, should slopes or curves of particular degrees should be painted with said material. There is a plus button next to the "Material Filters" title, that upon being clicked will add a new filter subcard with zeroed out values in fields, and a title that reads "New Filter" to encourage the user to name it. Each filter added is a subcard with a heading. In the headings there is a remove button, title and expand / collapse icon. Double clicking the title in these headings allows users to rename them, clicking remove will remove the filter (but first ask the user if they are sure with a confirmation dialog of some kind). Clicking expand / collapse will collapse the filter card or expand it to be edited.

- Altitude = float / number sequence input
- Slope = float / number sequence input
- Curve = float / number sequence input

----

## Environmental Edit Mode Properties
![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Environmental-Edit-Properties.jpg?raw=true)

Top of our properties window we have text input and a plus button. 
Idea here is when user provides a category name (must be unique) and clicks the plus, a new Environmental properties card will be added below it and represents a "Category" that holds settings amongst possibly many other unique Environmental Categories.

Each card has a heading with title of provided category name, a color picker, and a expand/collapse up/down arrow. Name can be changed by double clicking it which turns it into a text input with current name primed for rename. Hitting enter will commit to that change, esc will exit it. Upon committing to a new category name it needs to still be guarded against duplicates as each category must be unique. Native color picker is an arbitrary color that will be used in our preview window for this mode, nothing more (More on that later).

Lets go over each of the properties in each of the environmental category property cards

- ScaleMin = single float input
- ScaleMax = single float input
- Altitude = single float input, and this has an icon before the label
- Slope = single float input, and this has an icon before the label
- Spacing = number input
- Rot Axis = three checkboxes labeled X, Y and Z
- Max Deg = three  number inputs labeled X, Y and Z
- Align to normal = single checkbox
- Avoid Categories = This a listing of subcards that the user can build up. There is a title and a plus button. When user clicks plus button a new entry with the name <New Avoid Category> is added to our sub listing below it. This listing has a fixed height with a scrollbar so the user can add as many in here as they like. Once an avoid category is added user can double click the name to have that name turn into a drop down list of all available Categories added in our environmental properties (minus the current one). User pick from the dropdown list, dropdown closes and after ensuring that user has not already added this Category to the avoid category listing already, captures their selection and sets the entries title to selected name. Select box goes away and title is shown again. Off to the right of each avoid category listed item's title, is a remove button. Clicking this will remove that entry after confirming the user that they are sure they want to do that (confirmation dialog).
- Avoid footprint = single number input
- Self Overlap = single checkbox
- Allowed Materials = again another sub list here with a scroll bar, but this is not user curated, but instead just lists all the available materials terrains can have. Each listing has a tiny preview of the material, a title with the name of the material and a checkbox that by default should be unchecked.
- Models = again another sub list here that is user curated of models for this category. Off to the right of the Models title is a blue plus button. Once clicked it will add a new entry with a title of "Please pick model". Each entry here has a remove button, a title, and a object value field. (Ignore the expand / collapse toggle on these entries in the comp.. this was an oversight). When clicking the object value field, user is primed to select a model out in their project. Once a model has been assigned, the name of that model gets inherited onto the entries title. If use clicks remove, it will remove that entry after having confirmed with they user they are sure they want to do so (confirmation dialog again).

----

## Stamps Edit Mode Properties
![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Stamp-Edit-Properties.jpg?raw=true)

Top of our properties window we have text input and a plus button. Idea here is when user provides a category name (must be unique) and clicks the plus, a new Stamps properties card will be added below it and represents a "Category" that holds settings amongst possibly many other unique Stamp Categories.

Each card has a heading with title of provided category name, a color picker, and a expand/collapse up/down arrow. Name can be changed by double clicking it which turns it into a text input with current name primed for rename. Hitting enter will commit to that change, esc will exit it. Upon committing to a new category name it needs to still be guarded against duplicates as each category must be unique. Studio color picker is an arbitrary color that will be used in our preview window for this mode, nothing more (More on that later).

Lets go over each of the properties in each of the stamp category property cards

- ScaleMin = single float input
- ScaleMax = single float input
- Altitude = single float input, and this has an icon before the label
- Slope = single float input, and this has an icon before the label
- Spacing = number input
- Rot Axis = three checkboxes labeled X, Y and Z
- Max Deg = three  number inputs labeled X, Y and Z
- Align to normal = single checkbox
- Avoid Categories = This a listing of subcards that the user can build up. There is a title and a plus button. When user clicks plus button a new entry with the name <New Avoid Category> is added to our sub listing below it. This listing has a fixed height with a scrollbar so the user can add as many in here as they like. Once an avoid category is added user can double click the name to have that name turn into a drop down list of all available Categories added in our stamp properties (minus the current one). User pick from the dropdown list, dropdown closes and after ensuring that user has not already added this Category to the avoid category listing already, captures their selection and sets the entries title to selected name. Select box goes away and title is shown again. Off to the right of each avoid category listed item's title, is a remove button. Clicking this will remove that entry after confirming the user that they are sure they want to do that (confirmation dialog).
- Avoid footprint = single number input
- Self Overlap = single checkbox
- Allowed Materials = again another sub list here with a scroll bar, but this is not user curated, but instead just lists all the available materials terrains can have. Each listing has a tiny preview of the material, a title with the name of the material and a checkbox that by default should be unchecked.
- Models = again another sub list here that is user curated of models for this category. Off to the right of the Models title is a blue plus button. Once clicked it will add a new entry with a title of "Please pick model". Each entry here has a remove button, a title, and a object value field. (Ignore the expand / collapse toggle on these entries in the comp.. this was an oversight). When clicking the object value field, user is primed to select a model out in their project. Once a model has been assigned, the name of that model gets inherited onto the entries title. If use clicks remove, it will remove that entry after having confirmed with they user they are sure they want to do so (confirmation dialog again).

Its not lots on me that Stamps is exactly the same is Environmental, and that is by design.. the only difference is Environmental stay in the scene to be rendered.. stamps add or remove to the terrain and then go away and never are rendered.. but they very much want to have the same fine tuning features.. hence, they are the same, but different.

---
## Lighting Edit Mode Properties
![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Lighting-Edit-Properties.jpg?raw=true)

Very simple set of properties here. We have two cards here, one "Day / Night System" and the other "Atmosphere". Both these cards have a expand / collapse toggle button to the right of their labels.
Lets go over each property in both cards:

### Day / Night System
- Day Start Hour = number input that can't be below 1 or greater than 24
- Night Start Hour = number input that can't be below 1 or greater than 24
- Day Length = number input
- Night Length = number input

### Atmosphere
- Density = float input
- Offset = number input
- Color = studio color picker
- Decay = studio color picker
- Glare = number input
- Haze = number input

---

## Cave Edit Mode Properties
![default state](https://github.com/drolsen/terralux/blob/main/screenshots/Cave-Edit-Properties.jpg?raw=true)

Very simple set of properties here. We have two cards here, one "Cave Entrance" and the other "Cave Shape". Both these cards have a expand / collapse toggle button to the right of their labels.
Lets go over each property in both cards:

### Cave Entrance
- Amplitude = float input
- Direction = two float inputs labeled min and max
- Threshold = float input
- Frequency = float input
- Start of Z Fracture = float input

### Cave Shape
- Tube count = number input
- Tube Length = two float inputs labeled min and max
- Tube radius = number input

---

### Settings Edit Mode Properties
![default state](https://github.com/drolsen/terralux/blob/main/screenshots/World-Settings-Edit-Properties.jpg?raw=true)

Very simple set of properties here. We have a single relevant cards here called  "World Settings". This is what appears when user clicks the cog settings icon in the main toolbar.
Lets go over each property in both cards:

#### World Settings
- Seed = number input
- Vox = number input
- ResolutionXZ = number input
- Tile Size = float input
- Chunk XZ Size = number input (comp shows float, ignore that comp)
- Chunk Y Size = number input (comp show float, ignore that comp)
- Y Min World =  float input
- Y Headroom = float input
- World Start Z Position = float input
- Biome Shape Blend Size = float input
- Biome Mat Blend Size = float input
- Crust Above Size = float input
- Crust Below Size = float input
- Stamp Above Size = float input
- Stamp Below Size = float input
- Cave Above Size = float input
- Cave Below Size = float input
- Min Y = float input

The comp shows more properties cards below, but this is just a representation in how you can toggle open and close the World properties while under any of the edit modes.

Next we will move into preview window and its features, as well as how they differ from edit mode to edit mode.

---

## Preview Window
Lets break down the preview window features before anything else. 
Its important to note that we have two "Views" to the preview window. 2D and 3D views as well as supporting features that we will go over below.

![preview window sample dropdown](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-Sample-Size-Dropdown.jpg?raw=true) <br/>
We have a dropdown in the upper left hand corner that defines our preview sample size.  <br/>
![preview window sample dropdown open](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-Sample-Size-Dropdown-Open.jpg?raw=true) <br/>
There are only three options ever 1024x1024, 512x512 and 256x256. This is just a preview sample size, not the actual size of our biome / terrain. There is a hover state and selected state when mousing over this dropdown (honestly like how all our dropdowns should be colored for different states if you ask me).


We have some controls in the upper right hand corner that defines a few features:

![preview window controls in 2d view](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-Controls-2D-View.jpg?raw=true)
![preview window controls in 3d view](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-Controls-3D-View.jpg?raw=true) <br/>

- Grid icon (only enabled to be toggled on and off when in 2D view) that when clicked puts a grid over the preview window to help better visualize 2D pixel cells.
- 2D / 3D button. Clicking 2D will put the preview window into 2D view (first screenshot), clicking 3D will put preview window into 3D view (second screenshot).
- Zoom button. Clicking this will flyout two more buttons (plus and minus icons)that zooms our sample size in and out in either 2D or 2D view.
- Move button. Clicking this will flyout number inputs for X and Y for user to move to specific spots in our biome terrain and have it be sampled in our preview. Limits to how far you can move are defined by your biome size, this is the area you can move your preview window around in.
- Rotate button. Clicking this will flyout two buttons with left and right arrows. These will rotate the fixed camara around the preview sample by 45deg in 3D mode, 90deg in 2D mode.
- Lower left corner of the preview is arrows to denote a window resize drag spot; nothing more. User clicks and drags here, and they are resizing the window. Resizing however must maintain aspect ratio in order to respect our 2D grid zooming below (I think).

Lets now talk about 2D and 3D views.
## Preview Window Different Views

### 2D View
![preview window in 2d view with grid](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-2D-View-With-Grid.jpg?raw=true)
![preview window in 2d view with grid](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-2D-View-Without-Grid.jpg?raw=true)
Because we can't generate images via roblox API, the preview window's 2D mode must be a big grid of GUI frames that very their values between black and white for some edit modes, or a full color value in other edit modes (we will go over the rules for that over each of the requirements for preview window across the different edit modes coming up). The grid of frames in 2D that represents our pixel approximation is defined by our sample size. Moving around using the move tool doesn't redraw all our frames, but color shifts them based on our coordinates. Rotating again does a color shift by rotating our numbers 90deg. Zoom will zoom in 5 grid cells at a time, the max you can zoom out is defined by our sample size, the min you can zoom in is down to 1 cell taking up our entire preview window. For context, our sample size is acting like a resolution of our 2D preview if you will and sample size defines our max zoom out.

### 3D View 
![first time opening plugin](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-3D-View.jpg?raw=true)
Should be a fixed top down 45deg view of our sample size terrain generated in 3d space. Using the preview window's move tool will require a full regen of new area in the 3D view and might take time, but this is not runtime so who cares. Rotating the 3d view will rotate the camera around our sample by 45deg (vs 90deg in 2d mode). Zoom Will zoom the camera in and out giving a better closeup view of the sample to the end user (no limits yet on zoom, but I'm sure there will be some set at some point). Choosing a different sample size in 3D will make the generated terrain preview area larger or smaller for the end user.

Ok lets move into each edit modes unique usage of 2D and 3D views.

---

## Biome Edit Mode (First screenshot) 
![biome edit mode full comp 2d](https://github.com/drolsen/terralux/blob/main/comps/Biome-Edit-Mode-2D-preview.jpg?raw=true) <br/>
- 2D view shows a black and white approximation representation of our Biome amplitude and frequency etc settings that is used to generate our terrain shape. This gives artist a quick unique view into how their terrain shape is changing over various Biome edit settings, without committing to a full terrain generate. (Second screenshot) 

![biome edit mode full comp 3d](https://github.com/drolsen/terralux/blob/main/comps/Biome-Edit-Mode-3D-preview.jpg?raw=true) <br/>
- 3D view is a devoid of anything environmental models, no material work and is purely focused on showing off terrain's shape.. the bare shape. I recommend here in this edit mode we generate the terrain with a snow material and set its color to something like that of a mudbox red. The third and fourth screenshots show our Biome Edit Mode in full.

---

## Material Edit Mode
![material edit mode full comp 2d](https://github.com/drolsen/terralux/blob/main/comps/Material-Edit-Mode-2D-preview.jpg?raw=true) <br/>
- 2D view shows uses our defined colors we set in the header of each material properties card (firsts screenshot) as an approximation representation of our applied material locations (second screenshot). In our example here, we defined our grass material to be a layer of 0, so its applied first and over the entire terrain, and we gave it a preview color of red. Next we set a brick material to apply, give it a layer number, applied some filtering to it across slopes or curves and set its preview color to green. Lastly we applied cobble stone, set a layer number, applied some filtering to it and gave it a preview color of blue. The result in our 2D view here should be showing us a grid pixel approximation representation of each of our materials applicable areas (similar to a splat map, but not by any means.. rgb was just used for demo sakes).

![material edit mode full comp 3d](https://github.com/drolsen/terralux/blob/main/comps/Material-Edit-Mode-3D-preview.jpg?raw=true) <br/>
- 3D view is a just like our Biome 3D preview, except here we are actually applying our materials now.

In conjunction, these two views give the artist a way to quick observe where their materials are being painted in 2D mode, then can jump into 3D mode and observe them.

Next up is Environmental Edit mode.

---

## Environmental Edit Mode
![environmental edit mode full comp 2d view](https://github.com/drolsen/terralux/blob/main/comps/Environmental-Edit-Mode-2D.jpg?raw=true) <br/>
- 2D view uses our defined colors we set in the header of each groups properties card  as an approximation representation of our applied model's locations (second screenshot). In our example here, we defined our trees category and gave it a preview color of red. Same is true for our Cliff and Rocks categories set with preview colors of green and blue (respectively). The result in our 2D view here should be showing us a grid pixel approximation representation of each of our Environmental model's permitted position areas (similar to a splat map, but not by any means.. rgb was just used for demo sakes).

![environmental edit mode full comp 3d view](https://github.com/drolsen/terralux/blob/main/comps/Environmental-Edit-Mode-3D-preview.jpg?raw=true) <br/>
- 3D view is a just like our Materials 3D preview, except here we are actually positioning our environment category models.

---

## Stamps Edit Mode
Stamps does not have a 2D edit mode, and if the user happens to be in 2D edit mode while switching to stamps, they will be put into 3D mode automatically.

![stamps edit mode full comp](https://github.com/drolsen/terralux/blob/main/comps/Stamps-Edit-Mode-3D.jpg?raw=true) <br/>
- 3D view mode will now include Biome edit mode shape, Material edit mode painting, Environment Models and now stamps. 

However the preview window now will have a new option which toggles off Environment models if artist wants to clear them while testing either of the three edit modes.
![preview window toggle environmental option](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-Toggle-Environmental.jpg?raw=true)

---

### Lighting Edit Mode
Lighting does not have a 2D edit mode, and if the user happens to be in 2D edit mode while switching to stamps, they will be put into 3D mode automatically.

![lighting edit mode full comp](https://github.com/drolsen/terralux/blob/main/comps/Lighting-Edit-Mode-3D-preview.jpg?raw=true) <br/>
- 3D view mode will now include Biome, Material, Environmental, Stamps now. 

However the preview window now will have a new option which toggles off Environment models if artist wants to clear them while testing either of the three edit modes.
![preview window toggle environmental option](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-Toggle-Environmental.jpg?raw=true)

### Cave Edit Mode
Stamps does not have a 2D edit mode, and if the user happens to be in 2D edit mode while switching to stamps, they will be put into 3D mode automatically.

![cave edit mode full comp](https://github.com/drolsen/terralux/blob/main/comps/Caves-Edit-Mode-3D.jpg?raw=true) <br/>
- 3D view mode will now include Biome, Material, Environmental, Stamps now, but the preview window now will have a new option which toggles off Environment models if artist wants to clear them while testing either of the three edit modes.

However the preview window now will have a new option which toggles off Environment models if artist wants to clear them while testing either of the three edit modes.
![preview window toggle environmental option](https://github.com/drolsen/terralux/blob/main/screenshots/Preview-Toggle-Environmental.jpg?raw=true)

# Saving Data
Biomes/settings should be saved via plugin:SetSetting/GetSetting (per‑user, per‑machine), serialized to a ModuleScript/JSON that is hidden from the users best possible. We should be auto‑saving the current biome properties across all the edit modes whenever a value changes. When the user opens the plugin for the first time, a new JSON file should be crafted and there after read from to restore the users last editing session.

The core terrain generating code that will eventually consume TerraLux plugin data is not setup to read from any JSON file, but rather has all its values hardcoded right now. However the idea here is the user can feed their JSON session from TerraLux and have the code parse / generate that terrain runtime. Right now the entire setup is intended to be runtime, once that is perfected we will make a seperate project at having a build time feature too.

Important part to know right now is that we indeed what to have a persistent session based experince that is auto saving all changes to a under the hood JSON file / schema. This file will not only act as our way to make oure persisten experince, but eventually be used to feed these settings to our runtime terrain generator code as well.

# Plugin Iconography
We have a lot of icons to this plugin, and all of them can be found in our icons folder. Each should be named according to the section they live in (Main Toolbar, Properties window, Preview window) and given a name that describes their feature.

---

# Common Clarifications Points

1. **Scope of Settings**

   > *Only the existing settings and properties defined in this specification are supported. No additional or custom parameters will be exposed beyond what is outlined here.*

2. **Runtime vs Build-time**

   > *This plugin currently focuses only on runtime JSON configuration. Build-time terrain generation support will come later and is not part of this version.*

3. **JSON Output Structure**

   > *All plugin changes are written to a single monolithic JSON file. Biomes, world settings, and all other properties are combined into this file rather than stored separately.*

4. **World Settings**

   > *World-level properties (resolution, grid size, tile dimensions, seed, etc.) are already exposed in the World Settings panel as shown in the design comps. These values are directly editable from the plugin UI.*

5. **World Seed Input**

   > *World seed is exposed as a numeric input field. Randomization support may be added later, but is not included in the current version.*

6. **Presets**

   > *World and biome presets are not available yet. They will be introduced once the core plugin tool is stable and functional.*

7. **Height / Noise Layers**

   > *Noise layers are already represented as amplitude and frequency (Small, Medium, Large) inputs in the plugin UI. No additional layers or UI types will be added beyond what is specified in the comps.*

8. **Experimental Fields**

   > *Some properties (such as filters in materials and environmental edits) already use number sequence fields instead of simple numeric inputs. These are the only experimental input types included — stick to the specs for all others.*

9. **Caves / Crevices / Cones**

   > *All cave, crevice, and cone properties listed in the core scripts are already mapped to number inputs in the plugin UI. These features are disabled by simply not using them (e.g., setting amplitude to 0). There are no explicit on/off toggles at this stage.*

10. **Biome Boilerplate JSON**

    > *The plugin ships with a boilerplate JSON file. On first launch, this file is established and loaded. From then on, all changes are made directly to this file and it is reloaded each time the plugin starts.*

11. **Monolithic Biome Storage**

    > *All biomes are stored in the same monolithic JSON file. They are not broken into separate files.*

12. **Biome Assets**

    > *Biome asset selectors are ObjectValue fields pointing to models within the user’s project, not asset IDs. These allow users to bind in-project models directly.*

13. **Materials**

    > *Multiple material layers can be defined per biome. Each material can include its own filters. At least one material must be defined as layer `0` — this base layer applies across the entire terrain with no filters.*

14. **Vegetation & Stamps**

    > *The options shown in the specs and comps are the only vegetation and stamp controls available. No additional scatter or clustering rules are included beyond those already defined.*

15. **Runtime Preview**

    > *The plugin provides sample previews of biome/material edits inside the UI. Full results are always evaluated at runtime with the terrain generator.*

16. **Performance Controls**

    > *Performance-related settings (e.g., MAX\_GEN\_JOBS, ERASE\_STEPS\_PER\_TICK) are considered engine-level and are not exposed in the plugin UI.*

17. **Profiles / Platform Configs**

    > *No platform-specific profiles (e.g., PC vs tablet) are currently supported.*

18. **Import / Export**

    > *Export options may be introduced later, but are not part of the current version. Importing JSON back into the plugin is not currently supported, though this may be considered in the future.*

19. **Versioning & Undo**

    > *The plugin does not support versioned config saves. Instead, a simple undo/redo history (Ctrl+Z) will be provided for user edits.*

20. **UI Design Rules**

    > *The plugin UI follows the design comps: inline `label:value` fields, studio-native dropdowns (with hover/open/close states), and ObjectValue selectors for project assets. There are no sliders, custom dropdown widgets, or tooltips beyond what is shown in the comps.*

21. **JSON Storage Location**

   > *The plugin saves its monolithic JSON config to a location obscured from the user’s game project. This ensures it does not clutter developer assets, while still being fully accessible to the runtime system.*

22. **JSON Formatting**

   > *The JSON is always saved in human-readable (pretty-printed) format for easier debugging and editing if needed.*

23. **Save Behavior**

   > *All changes are automatically saved to JSON as soon as the user makes them. There is no manual Save/Export step in this version.*

24. **Invalid Input Handling**

   > *If a user enters an invalid value (e.g., out-of-range, non-numeric), the plugin ignores the input and makes no change. This fail-safe prevents corrupting the JSON file.*

25. **Preview Window**

   > *The preview window uses a grid of UIFrames sized by the sample-size dropdown. This is a **visual approximation** of a heightmap or splatmap — it is not an actual terrain preview but a representative pattern of the current settings.*

26. **Preview State**

   > *The plugin does not preserve collapsed/expanded panel states between sessions.*

27. **New Biomes**

   > *When a new biome is created, it is initialized with default starting values.*

28. **Biome Renaming**

   > *Biomes cannot be renamed in this version. They retain the names assigned by the boilerplate template.*

29. **Asset Selection**

   > *When selecting models (e.g., for vegetation or rocks), the user manually clicks the model in Explorer. The plugin then records that model’s name in the JSON.*

30. **Model Validation**

> *All models must have a defined PrimaryPart. Models without a PrimaryPart are rejected by the plugin.*

31. **Docking / Panel Behavior**

> *The plugin is not currently dockable as a permanent Studio side panel. It exists as its own floating window.*

32. **Error Feedback**

> *Errors such as missing JSON properties or invalid entries are not surfaced to the user. The plugin simply fails silently with no change applied.*

33. **Presets**

> *Biome/world presets will be implemented later as separate files. When available, users will be able to apply a preset to the currently edited biome, but this is not part of the current version.*

34. **Schema Versioning**

> *The plugin does not embed schema version numbers or metadata in the JSON at this stage.*


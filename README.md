# slicy
9-slice library for Love2D


https://user-images.githubusercontent.com/13891260/170899848-41cef538-efcf-44e2-8dae-637b390b208c.mov


## Installation
The only required file is `slicy.lua`, so simply drop it into the root of your Love2D project.

## About
9-slicing is a technique where only specific segments of an image are scaled. This allows for the corners (and even the edges in some cases) to suffer no distortion from resizing.

This library was created as a more modern version of [patchy](https://github.com/excessive/patchy), since it has some issues with its content window algorithm, is 3 years old as of writing this, and, to be quite frank, I just wanted to code this, it was fun.

### File format
The file format (`*.9.png`) is a regular PNG file, with 2 added rows and columns, 1 on each side. These will be called the "metadata" from now on. Here's an example of a `.9.png` file:

![ScaledPane 9](https://user-images.githubusercontent.com/13891260/170900996-57628dcc-4013-4744-96eb-0acb4f98e068.png)

The goal is to make this pane be adjustable as in the video demo above. To do this, we need to give slicy 2 bits of information:

- Which parts are safe to scale
- Which parts are safe to display content on

The scale part is easy: since this is pixel art, we can just grab a 1 pixel slice from the "edges" and call it a day. To do this, we mark the region (in this case, a single pixel on each axis) with black in the left and top metadata. The image outside this range will never be scaled, so the corners are safe.

The content part is... also easy! Same thing as the scale part, except we set the range with black pixels on the right and bottom metadata. Pixels outside this range will never be included in the content window (technically it only sets a padding, but for 99% of cases it should work fine just thinking of it as an this-is-ok-range).

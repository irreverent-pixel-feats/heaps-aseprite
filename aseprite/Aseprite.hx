package aseprite;

import ase.AnimationDirection;
import ase.Ase;
import ase.chunks.ChunkType;
import ase.chunks.LayerChunk;
import ase.chunks.TagsChunk;
import aseprite.Slice;
import aseprite.Tag;
import h2d.Object;
import h2d.ScaleGrid;
import h2d.Tile;
import h3d.mat.Texture;
import hxd.Pixels;
import hxd.fs.FileEntry;
import hxd.res.Resource;

class Aseprite {
  /** This option should be set before loading any texture **/
  public static var resizeToNextPowerOfTwo = false;

  public var ase:Ase;
  public var frames(default, null):Array<Frame> = [];
  public var layers(default, null):Array<LayerChunk> = [];
  public var tags(default, null):Map<String, Tag> = [];
  public var slices(default, null):Map<String, Slice> = [];
  public var palette(default, null):Palette;
  public var duration(default, null):Float = 0;

  var frameTags:TagsChunk;
  var texture:Texture;
  var tiles:Array<Tile>;
  var widthInTiles:Int;
  var heightInTiles:Int;

  public function new(bytes:haxe.io.Bytes) {
    loadBytes(bytes);
  }

  public static function fromBytes(b) {
    return new Aseprite(b);
  }

  public function getTexture():Texture {
    if (texture != null) return texture;
    loadTexture();
    return texture;
  }

  public function toTile():Tile {
    return Tile.fromTexture(getTexture());
  }

  public function toTiles():Array<Tile> {
    if (tiles != null) return tiles;

    var tile = toTile();
    tiles = [
      for (i in 0...frames.length) {
        var x = i % widthInTiles;
        var y = Math.floor(i / widthInTiles);
        tile.sub(x * ase.header.width, y * ase.header.height, ase.header.width, ase.header.height);
      }
    ];

    return tiles;
  }

  public function toScaleGrid(name:String, frame:Int = 0, ?parent:Object) {
    var slice = slices.get(name);
    if (slice == null) {
      trace('WARNING: A slice named "$name" does not exist on this Aseprite.');
      return null;
    }

    if (!slice.data.has9Slices) {
      trace('WARNING: Slice "$name" does not have 9-Slices enabled.');
      return null;
    }

    var sliceKey = slice.data.sliceKeys[frame];

    return new ScaleGrid(toTile().sub(sliceKey.xOrigin, sliceKey.yOrigin, sliceKey.width, sliceKey.height, -sliceKey.xPivot, -sliceKey.yPivot),
      sliceKey.xCenter, sliceKey.yCenter, parent);
  }

  public function getFrames():Array<AsepriteFrame> {
    var tiles = toTiles();
    return [
      for (frame in frames) {index: frame.index, tile: tiles[frame.index], duration: frame.duration}
    ];
  }

  public function getFrame(index:Int):AsepriteFrame {
    return {index: index, tile: toTiles()[index], duration: frames[index].duration};
  }

  public function getTag(name:String, direction:Int = -1, ?slice_name:String):Array<AsepriteFrame> {
    var tag = tags.get(name);
    if (tag == null) {
      trace('WARNING: A tag named "$name" does not exist on this Aseprite.');
      return null;
    }

    var slice:Slice = null;
    if (slice_name != null) {
      slice = slices.get(slice_name);
      if (slice == null) trace('WARNING: A slice named "$slice_name" does not exist on this Aseprite.');
    }

    var tiles = toTiles();
    var animation = [];

    function add_animation(frame:Int) {
      var sliceKey = slice == null ? null : getSliceKey(slice, frame);
      animation.push({
        index: frame,
        tile: sliceKey == null ? tiles[frame] : tiles[frame].sub(sliceKey.xOrigin, sliceKey.yOrigin, sliceKey.width, sliceKey.height, -sliceKey.xPivot,
          -sliceKey.yPivot),
        duration: frames[frame].duration
      });
    }

    if (tag.chunk.fromFrame == tag.chunk.toFrame) add_animation(tag.chunk.fromFrame);
    else switch (direction < 0 ? tag.chunk.animDirection : direction) {
      case AnimationDirection.FORWARD:
        for (i in tag.chunk.fromFrame...tag.chunk.toFrame + 1) add_animation(i);
      case AnimationDirection.REVERSE:
        var i = tag.chunk.toFrame;
        while (i >= tag.chunk.fromFrame) {
          add_animation(i);
          i--;
        }
      case AnimationDirection.PING_PONG:
        var i = tag.chunk.fromFrame;
        var advance = true;
        while (i >= tag.chunk.fromFrame || advance) {
          add_animation(i);
          if (advance && i >= tag.chunk.toFrame) advance = false;
          i += advance ? 1 : -1;
        }
    }
    return animation;
  }

  public function getSlice(name:String, frame:Int = 0):AsepriteFrame {
    var slice = slices.get(name);
    if (slice == null) {
      trace('WARNING: A slice named "$name" does not exist on this Aseprite.');
      return null;
    }

    var sliceKey = getSliceKey(slice, frame);
    var x = frame % widthInTiles;
    var y = Math.floor(frame / widthInTiles);

    return {
      index: frame,
      tile: toTile().sub(x * ase.header.width
        + sliceKey.xOrigin, y * ase.header.height
        + sliceKey.yOrigin, sliceKey.width, sliceKey.height,
        -sliceKey.xPivot,
        -sliceKey.yPivot),
      duration: frames[frame].duration
    }
  }

  public function getSlices(name:String):Array<AsepriteFrame> {
    var slice = slices.get(name);
    if (slice == null) {
      trace('WARNING: A slice named "$name" does not exist on this Aseprite.');
      return null;
    }

    var tile = toTile();

    return [
      for (i in 0...frames.length) {
        var sliceKey = getSliceKey(slice, i);
        var x = i % widthInTiles;
        var y = Math.floor(i / widthInTiles);
        {
          index: i,
          tile: tile.sub(x * ase.header.width + sliceKey.xOrigin, y * ase.header.height + sliceKey.yOrigin, sliceKey.width, sliceKey.height,
            slice.data.hasPivot ? -sliceKey.xPivot : 0, slice.data.hasPivot ? -sliceKey.yPivot : 0),
          duration: frames[i].duration
        }
      }
    ];
  }

  // public function watchCallback() { // not supported
  //   dispose();
  //   loadData();
  //   loadTexture();
  // }

  function dispose() {
    for (frame in frames) frame.dispose();
    frames.resize(0);
    layers.resize(0);
    tags.clear();
    slices.clear();
    tiles = null;
  }

  public function loadBytes(bytes:haxe.io.Bytes) {
    dispose();
    ase = Ase.fromBytes(bytes);

    for (chunk in ase.frames[0].chunks) {
      switch (chunk.header.type) {
        case ChunkType.LAYER:
          layers.push(cast chunk);
        case ChunkType.PALETTE:
          palette = new Palette(cast chunk);
        case ChunkType.TAGS:
          frameTags = cast chunk;

          for (frame_tag_data in frameTags.tags) {
            var animation_tag:Tag = new Tag(frame_tag_data);

            if (tags.exists(frame_tag_data.tagName)) {
              var num:Int = 1;
              var new_name:String = '${frame_tag_data.tagName}_$num';
              while (tags.exists(new_name)) {
                num++;
                new_name = '${frame_tag_data.tagName}_$num';
              }
              trace('WARNING: This file already contains tag named "${frame_tag_data.tagName}". It will be automatically reanamed to "$new_name"');
              tags[new_name] = animation_tag;
            }
            else {
              tags[frame_tag_data.tagName] = animation_tag;
            }
          }
        case ChunkType.SLICE:
          var new_slice = new Slice(cast chunk);
          slices[new_slice.name] = new_slice;
      }
    }

    for (i in 0...ase.frames.length) {
      var data = ase.frames[i];
      var frame:Frame = new Frame({
        index: i,
        sprite: this,
        frame: data
      });
      duration += frame.duration;
      frames.push(frame);
    }

    for (tag in tags) {
      for (j in tag.chunk.fromFrame...tag.chunk.toFrame + 1) {
        frames[j].tags.push(tag.name);
      }
    }
  }

  function loadTexture() {
    widthInTiles = 1;
    heightInTiles = 1;

    for (i in 0...frames.length) {
      var y = Math.floor(i / widthInTiles);
      if (y >= heightInTiles) {
        heightInTiles++;
        widthInTiles++;
      }
    }

    var textureWidth = ase.header.width * widthInTiles;
    var textureHeight = ase.header.height * heightInTiles;
    if (resizeToNextPowerOfTwo) {
      textureWidth = next_power_of_2(textureWidth);
      textureHeight = next_power_of_2(textureHeight);
    }

    var pixels = Pixels.alloc(textureWidth, textureHeight, RGBA);

    for (i in 0...frames.length) {
      var x = i % widthInTiles;
      var y = Math.floor(i / widthInTiles);
      pixels.blit(ase.header.width * x, ase.header.height * y, frames[i].pixels, 0, 0, frames[i].pixels.width, frames[i].pixels.height);
    }

    if (texture == null) {
      texture = Texture.fromPixels(pixels);
      // watch(watchCallback); // not supported
    }
    else {
      var t = Texture.fromPixels(pixels);
      texture.swapTexture(t);
      texture.alloc();
      t.dispose();
    }

    pixels.dispose();
  }

  inline function getSliceKey(slice:Slice, frame:Int) {
    var sliceKey = null;
    if (slice.data.numSliceKeys > 0) {
      var i = slice.data.numSliceKeys;
      while (i > 0) {
        i--;
        if (frame >= slice.data.sliceKeys[i].frameNumber) {
          sliceKey = slice.data.sliceKeys[i];
          i = 0;
        }
      }
    }
    return sliceKey;
  }

  inline function next_power_of_2(v:Int) {
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
  }
}

typedef AsepriteFrame = {index:Int, tile:Tile, duration:Int}

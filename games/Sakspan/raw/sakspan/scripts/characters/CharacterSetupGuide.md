# Character Setup Guide

## Overview
This guide explains how to set up the character selection system for Sakspan.

## Character Scene Structure
You need to create 5 character scene files in `res://scenes/characters/`:

1. `PinkCharacter.tscn`
2. `RedCharacter.tscn` 
3. `BlueCharacter.tscn`
4. `GreenCharacter.tscn`
5. `YellowCharacter.tscn`

## How to Create Character Scenes

### Step 1: Create Base Character Scene
1. Open your existing player scene (`res://scenes/player.tscn`)
2. Save it as `res://scenes/characters/PinkCharacter.tscn`

### Step 2: Modify Character Script
1. In the scene, change the script from `player.gd` to `res://scripts/characters/PinkCharacter.gd`
2. The character will automatically get the pink color and character index

### Step 3: Repeat for Other Characters
1. Duplicate `PinkCharacter.tscn` and rename to `RedCharacter.tscn`
2. Change the script to `res://scripts/characters/RedCharacter.gd`
3. Repeat for Blue, Green, and Yellow characters

### Step 4: Customize Sprites (Optional)
If you have different sprites for each character:
1. In each character scene, replace the AnimatedSprite2D texture
2. Use the sprites from your `sprites/` folder (Blue_Monster, Green_Monster, etc.)

## Character Selection Flow
1. Players select characters in the lobby wait room
2. Selection is synced via NetworkManager and LobbySync
3. When the game starts, CharacterFactory creates the correct character type
4. Each character inherits from PlayerCharacter but has unique appearance/properties

## Files Created
- `CharacterFactory.gd` - Creates character instances
- `PinkCharacter.gd` - Pink character class
- `RedCharacter.gd` - Red character class  
- `BlueCharacter.gd` - Blue character class
- `GreenCharacter.gd` - Green character class
- `YellowCharacter.gd` - Yellow character class

## Integration Points
- `NetworkManager.gd` - Enhanced with character selection functions
- `LobbySync.gd` - Already handles character selection RPCs
- `world_new.gd` - Modified to spawn selected characters
- `lobby_wait_room_menu.gd` - Already has character selection UI

---

# Lifewood Game Collection Launcher

A unified, elegant launcher for all games developed by the Lifewood team.

## About The Project

This project is the official game launcher for the Lifewood Game Collection. It is designed to provide a single, beautiful, and professional platform to access, manage, and play our team's games. The launcher is data-driven, meaning new games can be added easily without needing to modify the launcher's source code.

### Features

*   **Dynamic Game Library:** Automatically populates the library by reading a central `GamesList.json` file.
*   **Data-Driven:** Add new games by simply editing a text file and adding a folder.
*   **Automatic Folder Creation:** The launcher will create the necessary game directories on first launch if they are missing.
*   **Box Art Support:** Automatically finds and displays `art.png` or `art.jpg` for each game, with a beautiful placeholder as a fallback.
*   **Direct Game Launching:** Launches the exported `.exe` for each game.
*   **Elegant UI:** A clean, nature-inspired user interface built with the Lifewood color palette.

## Getting Started

To get a local copy up and running, follow these simple steps.

### Prerequisites

*   **Godot Engine v4.4.1.stable**
*   **Git** and a Git client (like GitHub Desktop)

### Installation

1.  Clone the repository to your local machine:
    ```sh
    git clone https://github.com/MarkJanzenB/Lifewood-Games.git
    ```
2.  Open the Godot Project Manager and import the project by selecting the `project.godot` file.

---

## **How to Integrate Your Game (For Teammates)**

To ensure our main project remains stable, you will do all of your work in a dedicated branch. Follow these steps carefully to add your game to the Lifewood Launcher.

### Step 1: Create Your Development Branch

**Do this before making any changes!** This branch will be your personal workspace.

1.  Make sure you have the latest version of the `main` branch. In GitHub Desktop, fetch the origin and pull the latest changes.
2.  Create a new branch from `main`.
3.  Name your branch using this exact format: **`Lifewood:{YourGameName}`**.
    *   **Example:** If your game is named "Epic Adventure", your branch name will be `Lifewood:EpicAdventure`.
4.  Publish the branch to GitHub immediately so we know you are working on it. You will now be working in this branch for all the following steps.

### Step 2: Create Your Game's Folders

This is the most important step for project organization.

1.  In your local project folder, navigate to the **`games`** directory.
2.  Inside `games`, create a **new folder** for your game. The name should be a short, unique identifier (e.g., `EpicAdventure`, `PixelRacer`). This is your **`{gamefolder}`**.
3.  Inside your new `{gamefolder}`, create another folder and name it exactly **`Raw`**.

### Step 3: Add Your Game's Project Files

The `Raw` folder is for source control and will contain your game's complete Godot project.

*   Copy your **entire Godot game project** (all files and folders, including `project.godot`) and paste it inside the **`Raw`** folder you just created.

### Step 4: Add Your Game's Assets

The launcher needs two key assets from you, placed in your `{gamefolder}` (NOT inside `Raw`).

1.  **Box Art:** Add your game's box art to your `{gamefolder}`. It **must** be named either `art.png` or `art.jpg` and exactly 235px x 321px.
2.  **Exported Game:** Export your game from Godot as a Windows runnable (`.exe`). Place the exported `.exe` file inside your `{gamefolder}`. It **must** be named exactly the same as your `{gamefolder}`. For example, if your folder is `EpicAdventure`, the executable must be `EpicAdventure.exe`.

### Step 5: Update the `GamesList.json` File

This is the final step that makes the launcher recognize your game.

1.  In the root of the launcher project, open the `GamesList.json` file.
2.  Add a new entry for your game to the `"games"` list. Follow the exact format of the other entries.

**Example:** To add a game in a folder named `MyAwesomeGame`:
```json
{
  "games": [
    {
      "title": "My Awesome Game",
      "folder": "MyAwesomeGame"
    },
    {
      "title": "My First Game",
      "folder": "MyFirstGame"
    }
  ]
}
```
> **Note:** Add your new game to the **top of the list** to avoid merge conflicts with other teammates. Be careful not to leave a trailing comma after your entry if it's not the last one!

### Final Directory Structure Check

After completing all steps, the structure for your game's integration should look like this:
```
lifewood-games/
├── games/
│   ├── EpicAdventure/
│   │   ├── art.png                 <-- Your box art
│   │   ├── EpicAdventure.exe       <-- Your exported game
│   │   └── Raw/                    <-- Your game's source project folder
│   │       ├── project.godot
│   │       ├── scenes/
│   │       └── scripts/
│   │
│   └── ... (Other games)
│
├── Scenes/
├── Scripts/
├── Assets/
├── project.godot
└── GamesList.json                  <-- The file you edited

```

### Step 6: Commit and Push Your Changes

1.  Open GitHub Desktop. You will see all the new files you've added.
2.  Create a clear commit message, for example: `feat: Integrate [Your Game Name]`.
3.  Commit the changes to your `Lifewood:{YourGameName}` branch.
4.  **Push** the changes to the remote repository.

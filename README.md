# Club Manager for Trackmania

Club Manager is a tool designed to help you organize and manage your Trackmania Club activities (campaigns, rooms, and folders) more efficiently. 

## Features

### Club Organization
- **Visual Tree-View**: Manage all your club campaigns, rooms, and folders in a structured layout.
- **Easy Management**: Quickly reorder, rename, and move activities between folders.
- **Room Mirroring**: Create rooms that automatically link to and update from a parent campaign.

### Map Curation & TMX Integration
- **Advanced Search**: Find maps on [Trackmania Exchange (TMX)](https://trackmania.exchange) using filters for name, author, awards, time range, and tags.
- **Collaborator Search**: Full support for finding maps where a mapper is an author but not the uploader.
- **Automatic Audits**: Keep your club campaigns and rooms synced with any TMX search. See exactly what has changed and sync everything with a single click.
- **Intelligent Category Sync**: Automatically stabilizes campaign categories during updates to prevent Nadeo API InternalServerErrors.
- **Metadata Overrides**: Customise difficulty, tags, and map names locally without affecting the TMX source.
- **Guardrails**: Flags maps that might exceed game limits (large file sizes or high display costs) before you add them.
- **Subscription System**: Efficient configuration storage (saving only modified filters) to keep your club data lean.

### Local Map Browser
- **Direct Access**: Browse and add maps directly from your local `Documents/Trackmania/Maps/` folder without leaving the game.

## Developer Verification (Local)

To ensure code integrity and prevent regressions (such as broken TMX protocols or UI elements), use the Go-based verification tool:

1. Ensure [Go](https://go.dev/) is installed.
2. Run the verification script:
   ```pwsh
   go run scripts/verify.go
   ```
3. The script will verify TMX author flags, syntax consistency, and UI manifest presence.

---
*Developed by Arrold*


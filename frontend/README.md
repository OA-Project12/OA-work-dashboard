# Orbit — React frontend

Responsive React frontend workspace for the Trello-like task management product. The active app is built with React 19, Vite 8, JSX, and plain CSS. The earlier HTML concept is preserved at `reference-prototype.html`.

## Run locally

Use Node.js 20.19+ or 22.12+.

```sh
npm install
npm run dev
```

Vite prints a local URL. Create a production bundle with `npm run build`, then preview it with `npm run preview`.

## Current React flows

- Board navigation and responsive Kanban lists
- Search and filters by member, label, and due date
- Create, edit, and delete tasks
- Assign members, change list, set due dates, and add labels
- Add comments and view recent activity
- Notifications popover and accessible task dialog
- Browser-local persistence for prototype tasks

Task state currently stays in the browser's local storage. It is not yet connected to Supabase. The earlier full design and requirement-coverage explorer remains available in `reference-prototype.html`.

## Supabase connection

The database schema is maintained in `../supabase/migrations/`. Next, wire Supabase Auth and connect workspaces, boards, lists, cards, assignments, comments, and notifications through the RLS-protected client. Use only a publishable key in browser code; never expose a service-role or secret key. Keep local configuration in an ignored `.env` file.

The schema's implementation notes and open decisions are in `../supabase/schema-notes.md`. Add loading, empty, error, permission-denied, conflict, and saved states before connecting production data. Keep advanced modules behind approved feature flags.

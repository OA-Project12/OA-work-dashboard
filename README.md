# OA Work Dashboard

A task management dashboard prototype based on the Trello feature requirement matrix.

## Frontend

The React application lives in [frontend/](frontend/). See its README for local setup and development commands.

## Supabase

Database migrations and schema notes live in [supabase/](supabase/). The schema was applied to the Supabase project; see the notes for RLS, required Storage setup, and backend flows that still need implementation.

## Current scope

The frontend is a React prototype with browser-local task persistence. Supabase Auth and live data access are planned next; the browser app must use only a publishable key and rely on RLS, never a service-role key.

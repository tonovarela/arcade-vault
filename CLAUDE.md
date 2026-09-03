# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Project

Arcade Vault — online gaming platform where users play classic arcade games and compete for points on per-game leaderboards. Uses **Spec Driven Design** via the `/spec` and `/spec-impl` skills from `npx skills@latest add Klerith/fernando-skills` (see `skills-lock.json`).

## Stack

- **Next.js 16.2.6** with App Router — read `node_modules/next/dist/docs/` before writing Next.js code; APIs differ from training data
- **React 19.2.4**
- **Tailwind CSS v4** (PostCSS plugin via `@tailwindcss/postcss`)
- **TypeScript**
- **Supabase** (`@supabase/ssr`, `@supabase/supabase-js`) — auth + games/scores persistence
- **Resend** — contact form email delivery
- **Prettier + ESLint** (`eslint-config-next`) — formato y lint

No test runner configured.

## Tooling

Scripts (`package.json`): `dev`, `build`, `start`, `lint` (`eslint`), `format` (`prettier --write`), `format:check`.

- **Hook PostToolUse** (`.claude/settings.json` → `.claude/hooks/format-and-lint.sh`): tras cada `Write|Edit|MultiEdit|NotebookEdit|Bash` pasa Prettier a los archivos tocados, elimina espacios finales de línea y corre `eslint --fix` sobre `.ts/.tsx/.js/.jsx`. Si ESLint deja errores que `--fix` no resuelve, sale con código 2 y el detalle vuelve a Claude para que los corrija. **No hace falta formatear a mano después de editar.**
- **`.prettierrc`**: comillas simples, semicolons, `printWidth` 80, `trailingComma: all`, `endOfLine: lf`.
- **`.mcp.json`**: servidor MCP de Supabase (HTTP, `project_ref` fijo) con features docs/account/database/debugging/development/functions/branching. Es la vía para inspeccionar la DB (`list_tables`, `execute_sql`, `get_advisors`, `apply_migration`).
- **`.env`** (no versionado, plantilla en `.env.template`): claves de Supabase y Resend.

## Skills

Usa siempre `/frontend-design` para diseñar la interfaz de usuario.

- **`/spec` y `/spec-impl`** — skills base de Spec Driven Design, instalados en `.agents/skills/` desde `Klerith/fernando-skills` (ver `skills-lock.json`).
- **`/spec-impl-game`** (`.claude/skills/spec-impl-game/`, espejado en `.agents/skills/`) — variante de `/spec-impl` para specs de juegos: mismo flujo (Fases 1–4) y al terminar la implementación encadena automáticamente `@skin-designer` y luego `@mobile-porter` de forma secuencial.
- **`/add-game`** (`.claude/skills/add-game/`) — genera el spec de un juego canvas nuevo (componente React, play-page, fila en la tabla `games` de Supabase y wiring del modal de leaderboard). Acepta una carpeta de `references/started-games/` o una descripción libre. **No escribe código**, solo produce `specs/NN-<slug>-game.md`.

## Agentes

- **`game-planner`** — sugiere el próximo juego a implementar evaluando diversidad, factibilidad y reconocimiento clásico. To-do persistente en `references/game-suggestions-todo.md`. Úsalo con "qué juego sigue". Detalle: `.claude/agents/game-planner.md`.
- **`game-jam`** — dado un tema, genera ≥2 specs completos en `specs/game-jam/<game-id>/`. Úsalo con "game jam: \<tema\>". Detalle: `.claude/agents/game-jam.md`.
- **`skin-designer`** — aplica los 3 skins canónicos (classic, retro, neon) a un juego. Estado en `references/game-with-themes.md`. Úsalo con "aplica skins a \<juego\>". Detalle: `.claude/agents/skin-designer.md`.
- **`mobile-porter`** — añade controles táctiles (spec 10) a un juego sin tocar el componente canvas. Úsalo con "porta \<juego\> a mobile". Detalle: `.claude/agents/mobile-porter.md`.
- **`game-performance-booster`** — audita y corrige los 7 patrones de performance (spec 12) en un juego. Úsalo con "optimiza \<juego\>". Detalle: `.claude/agents/game-performance-booster.md`.
- **`security-auditor`** — audita seguridad de DB Supabase (RLS, políticas, advisors) y app Next.js (headers, proxy.ts, secretos, deps). Solo lectura. Bitácora en `references/security/audit-log.md`, checklist en `references/security/security-checklist.md`. Úsalo con "audita seguridad". Detalle: `.claude/agents/security-auditor.md`.

## Architecture

App Router exclusively — no `pages/` directory.

### Routes (`app/`)

- `layout.tsx` — root layout (Geist fonts, global CSS, `UserContext` provider, `Nav`)
- `page.tsx` — home / landing
- `about/` — about + contact form
- `api/contact/route.ts` — Resend-backed contact endpoint
- `auth/page.tsx` — login / signup con Supabase
- `auth/callback/route.ts` — route handler que canjea el `code` OAuth/email por sesión (`exchangeCodeForSession`) y redirige
- `auth/reset-password/page.tsx` — cambio de contraseña, valida contra `PASSWORD_REGEX` (≥8, mayúscula, minúscula, dígito y símbolo)
- `games/page.tsx` + `games/GamesGrid.tsx` — índice de juegos, leído desde la tabla `games` de Supabase
- `games/[id]/page.tsx` — detalle dinámico con ruta anidada `play/`
- `games/<juego>/play/page.tsx` — play-pages concretas: `arkanoid`, `asteroids`, `frogger`, `snake`, `tetris`
  (consulta `references/implemented-games.md` para saber qué hay implementado y cómo añadir uno nuevo)
- `hall-of-fame/page.tsx` + `HallOfFameClient.tsx` — leaderboard desde la tabla `scores`
- `pokemon-counter/page.tsx` — página suelta de demo/ejercicio (contador con sprites de PokeAPI); no forma parte del catálogo de juegos
- `context/UserContext.tsx` — contexto client-side del usuario autenticado
- `data/` — **vacío / legado**: el catálogo dejó de ser estático y ahora vive en Supabase. No importes de aquí ni lo repueble.
- `RevealObserver.tsx` — scroll-reveal animations

### Shared code

- `components/Nav.tsx` — top navigation
- `components/MobileGamepad.tsx` + `MobileGamepad.module.css` — gamepad táctil reutilizable, cableado desde las play-pages (nunca desde el componente canvas)
- `components/games/` — canvas game implementations (`ArkanoidGame`, `AsteroidsGame`, `FroggerGame`, `SnakeGame`, `TetrisGame`)
- `lib/supabase/` — `client.ts` (browser), `server.ts` (RSC/route handlers), `types.ts` (`GameRow`, `ScoreRow`)
- `proxy.ts` — proxy de Next.js 16 (sustituto del middleware): redirige a `/` si ya hay cookie de sesión; `matcher: '/auth'`
- `next.config.ts` — cabeceras de seguridad globales (`X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `X-DNS-Prefetch-Control`) y `allowedDevOrigins`
- `public/` — sprite sheets (`spritesheet-breakout.png`, `fruits.png`) y audio (`ball-bounce.mp3`, `break-sound.mp3`)
- `demos/` — scratch de ejemplos sueltos, fuera del build de rutas

### Specs

`specs/` guarda la historia de Spec Driven Design, numerada `01`–`15`: pantallas y landing (01–03), Supabase y leaderboard (04, 06), juegos (05 asteroids, 07 tetris, 08 arkanoid, 09 snake), mobile (10 controles táctiles, 11 skin neón del gamepad), performance (12) y auth/seguridad (13 auth, 14 RLS + password + headers, 15 hardening).

`specs/game-jam/` guarda los jams temáticos (`frogger/`, `space-invaders/`), un subdirectorio por juego.

### References

`references/` es la memoria de proyecto que mantienen los agentes:

- `implemented-games.md` — tabla de juegos en el catálogo (id, título, categoría, color)
- `game-suggestions-todo.md` — cola de propuestas de `game-planner`
- `game-with-themes.md` — matriz de skins por juego de `skin-designer`
- `security/` — `audit-log.md` (bitácora de `security-auditor`) y `security-checklist.md`
- `started-games/` — implementaciones vanilla JS de origen (asteroids, tetris, arkanoid) que sirven de punto de partida
- `source-assets/`, `gamepad-assets/`, `templates/` — sprites, audio y maquetas HTML/JSX de referencia

## Conventions

- Server Components by default; add `"use client"` only when needed (game canvases, auth context, interactive forms).
- New routes: folder under `app/` with `page.tsx`.
- Shared UI in `components/`; game logic colocated in `components/games/<Game>.tsx`.
- Supabase: import from `lib/supabase/server` in RSC / route handlers, `lib/supabase/client` in client components.
- New games follow the existing pattern: spec in `specs/`, canvas component in `components/games/`, route under `app/games/<name>/play/`, fila en la tabla `games` y score writes through `lib/supabase`.
- El gamepad móvil se cablea en la play-page, nunca dentro del componente canvas.

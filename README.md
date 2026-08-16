# IKARS Instructor Platform

## Development safety

- The approved UI prototype is preserved by the Git tag `approved-ui-prototype`.
- Database work is developed in `feature/supabase-foundation`.
- `supabase/config.toml` contains only a local placeholder project ID.
- Never link this repository to an existing IKARS, GoDrive, rental CRM, or assistant Supabase project.
- Apply migrations only to a new dedicated instructor-platform test project after a reviewed dry run and backup check.

Отдельная демонстрационная среда CRM независимого автоинструктора, публичного каталога и школьного виджета.

## Безопасность текущего этапа

- используются только вымышленные данные из `src/demo-data.js`;
- существующие Supabase-проекты IKARS не подключены;
- `.env` исключён из Git;
- нажатия телефона и статистика пока сохраняются только в `localStorage` браузера;
- событие `phone_click` означает попытку звонка, а не подтверждённый разговор.

## Локальный запуск

```powershell
npm install
npm run dev
```

До создания отдельного демонстрационного Supabase-проекта оставьте `VITE_DEMO_MODE=true`.

## Режимы данных

- `VITE_DEMO_MODE=true` включён по умолчанию и не требует подключения к Supabase.
- Ученики, занятия и счётчики деморежима сохраняются только в текущем браузере под ключом `ikars-instructor-demo-workspace-v1`.
- Интерфейс работает через единый слой данных в `src/lib`, поэтому при подключении тестовой базы утверждённый календарь переписывать не потребуется.
- Supabase-режим не запустится без URL, publishable key и инициализированного клиента. Подключение к другой базе «по умолчанию» исключено.
- Авторизация и изолированные по инструктору операции подготовлены в `src/lib/supabase-repository.js`, но будут активированы только после создания отдельного тестового проекта.

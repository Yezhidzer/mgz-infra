# System Map

## Назначение
Этот файл фиксирует текущую карту системы для дальнейшего Helm/Kubernetes-деплоя.
Цель: сначала зафиксировать состав сервисов, протоколы, зависимости, порты, конфигурацию и точки неопределённости, потом на этой базе писать charts/manifests.

## Границы системы
Сейчас в системе подтверждены:
- `api-gateway`
- `auth-service`
- `chat-service`
- `user-service`
- `postgresql`
- `redis`
- `minio`

Пока не подтверждены по текущим репозиториям:
- `kafka`
- `elasticsearch`

## Схема взаимодействия
```text
Client
  -> api-gateway (HTTP :8080)
      -> auth-service (HTTP :8081)
      -> chat-service (gRPC :50051)
      -> user-service (gRPC :50052 в общем compose / :50051 по умолчанию в самом repo)

auth-service -> PostgreSQL(auth)
auth-service -> Redis

chat-service -> PostgreSQL(chat_message)
chat-service -> Redis

user-service -> PostgreSQL(user_service)
user-service -> MinIO(S3)
```

## Сервисы

### 1. api-gateway
**Репозиторий:** `Bobb1n/mgz_auth`  
**Путь в repo:** `api_gateway/`

**Роль**
- Единая внешняя точка входа в систему.
- Принимает HTTP-запросы от клиента.
- Проверяет JWT для защищённых маршрутов.
- Проксирует запросы во внутренние сервисы.
- Для chat уже выступает как HTTP-фасад над внутренним gRPC-сервисом.

**Протокол / порт**
- Внешний протокол: `HTTP`
- Внутренний порт контейнера: `8080`
- Наружу сейчас публикуется именно он.

**Входящие маршруты**
- `/health`
- `/api/v1/auth/*`
- `/v1/*` — фасад над chat-service
- `/api/v1/users*` — зарезервировано под user-service, но полноценный HTTP-фасад ещё не завершён

**Зависимости**
- `auth-service`
- `chat-service`
- `user-service`

**Основные env**
- `GATEWAY_PORT`
- `AUTH_SERVICE_URL`
- `CHAT_SERVICE_URL`
- `USER_SERVICE_URL`
- `JWT_SECRET`

**Secret env**
- `JWT_SECRET`

**Kubernetes-роль**
- `Deployment`
- `Service`
- `Ingress` или внешний `Service` типа `LoadBalancer`/`NodePort`

**Health/Probe**
- `GET /health`

**Неопределённости / TODO**
- Нормализовать схему доступа к `user-service`: сейчас user gRPC-only, а в gateway заготовлен HTTP-прокси-путь.
- Зафиксировать окончательный способ общения с `chat-service`: через HTTP-фасад gateway для клиентов и gRPC внутри.

---

### 2. auth-service
**Репозиторий:** `Bobb1n/mgz_auth`  
**Путь в repo:** `auth_service/`

**Роль**
- Регистрация пользователя.
- Логин по `email` или `username`.
- Выпуск `access_token` и `refresh_token`.
- Обновление access по refresh.
- Logout через blacklist токенов.

**Протокол / порт**
- Протокол: `HTTP`
- Внутренний порт контейнера: `8081`

**Маршруты**
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`

**Зависимости**
- `postgresql` — БД `auth`
- `redis` — blacklist токенов

**Основные env**
- `SERVER_PORT`
- `DATABASE_URL`
- `REDIS_URL`
- `JWT_SECRET`
- `JWT_ACCESS_TTL_MINUTES`
- `JWT_REFRESH_TTL_DAYS`

**Secret env**
- `DATABASE_URL` или раздельно DB credentials
- `JWT_SECRET`
- `REDIS_URL`, если будет содержать пароль

**Хранилище**
- Постоянные данные: в PostgreSQL
- Временные/служебные данные: в Redis

**Миграции**
- Нужен отдельный `Job`/`init` шаг для миграций auth БД

**Kubernetes-роль**
- `Deployment`
- `Service`
- `Job` для миграций

**Health/Probe**
- Надо проверить наличие отдельного health endpoint в коде; если нет — добавить.

---

### 3. chat-service
**Репозиторий:** `S1FFFkA/chat-message-mgz`

**Роль**
- Личные чаты.
- Отправка и хранение сообщений.
- Статусы сообщений (`sent`, `delivered`, `read`).
- Список чатов пользователя.
- Превью чата.
- Cursor pagination по сообщениям.

**Протокол / порт**
- Протокол: `gRPC`
- Порт: `50051`

**Методы MVP**
- `CreateDirectChat`
- `DeleteChat`
- `CreateMessage`
- `SendMessage`
- `UpdateMessageStatus`
- `GetChatPreview`
- `GetLastMessages`
- `ListUserChats`
- `MarkChatRead`

**Зависимости**
- `postgresql` — БД `chat_message`
- `redis`

**Основные env**
- `GRPC_PORT`
- `DATABASE_URL`
- `REDIS_ADDR`
- `REDIS_DB`
- `CACHE_TTL`

**Secret env**
- `DATABASE_URL` или раздельно DB credentials
- `REDIS_ADDR`, если Redis будет с паролем

**Хранилище**
- Постоянные данные: PostgreSQL
- Кэш/служебные данные: Redis

**Миграции**
- Нужен отдельный `Job`/`init` шаг для миграций chat БД

**Kubernetes-роль**
- `Deployment`
- `Service` (ClusterIP)
- `Job` для миграций

**Health/Probe**
- gRPC health-check не зафиксирован. Для k8s лучше добавить gRPC health service или отдельный HTTP `/healthz`.

---

### 4. user-service
**Репозиторий:** `S1FFFkA/user-mgz`

**Роль**
- CRUD пользователя.
- Список пользователей.
- Работа с фото пользователя.
- Выдача `presigned URL` для загрузки и скачивания фото.
- Подтверждение загрузки фото в S3/MinIO.

**Протокол / порт**
- Протокол: `gRPC`
- По умолчанию в собственном repo: `50051`
- В общем compose из `mgz_auth`: `50052`

**Критичная неопределённость**
- Нужно выбрать один канонический порт для Kubernetes. Рекомендуемо: `50052`, потому что он уже разведен с `chat-service` в общем compose.

**Методы MVP**
- `CreateUser`
- `GetUser`
- `UpdateUser`
- `DeleteUser`
- `ListUsers`
- `GetUserPhotoUploadUrl`
- `ConfirmUserPhotoUpload`
- `DeleteUserPhoto`
- `GetUserPhotoDownloadUrl`

**Зависимости**
- `postgresql` — БД `user_service`
- `minio` / S3-compatible storage

**Основные env**
- `GRPC_PORT`
- `DATABASE_URL`
- `S3_ENDPOINT`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`
- `S3_BUCKET`
- `S3_USE_SSL`

**Secret env**
- `DATABASE_URL` или раздельно DB credentials
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`

**Хранилище**
- Метаданные: PostgreSQL
- Фото: MinIO / S3

**Миграции**
- Нужен отдельный `Job`/`init` шаг для миграций user БД

**Kubernetes-роль**
- `Deployment`
- `Service` (ClusterIP)
- `Job` для миграций

**Health/Probe**
- gRPC health-check не зафиксирован. Для k8s лучше добавить gRPC health service или отдельный HTTP `/healthz`.

---

## Инфраструктурные компоненты

### 5. postgresql
**Роль**
- Основное хранилище данных.

**Текущая модель**
- Один инстанс PostgreSQL.
- Внутри создаются отдельные базы:
  - `auth`
  - `chat_message`
  - `user_service`

**Решение для первого staging**
- Один `StatefulSet` PostgreSQL.
- Отдельный PVC.
- Отдельные migration jobs по сервисам.

**Kubernetes-роль**
- Готовый Helm chart или `StatefulSet + Service + PVC + Secret`

---

### 6. redis
**Роль**
- Blacklist JWT/refresh токенов в auth-service.
- Кэш/служебные данные chat-service.

**Решение для первого staging**
- Один Redis instance.
- Без кластера.
- Внутренний `ClusterIP`.

**Kubernetes-роль**
- Готовый Helm chart или `Deployment/StatefulSet + Service`

---

### 7. minio
**Роль**
- S3-compatible object storage для фото пользователей.

**Использует**
- `user-service`

**Основные параметры**
- endpoint
- access key
- secret key
- bucket `users`

**Решение для первого staging**
- Один MinIO instance.
- Один PVC.
- Bucket bootstrap шаг при деплое.

**Kubernetes-роль**
- Готовый Helm chart/operator или `Deployment/StatefulSet + Service + PVC + bootstrap Job`

---

## Компоненты, которых пока нет в подтверждённом коде

### kafka
- В текущих трёх репозиториях явных интеграций не найдено.
- Пока не включать в первый рабочий staging без подтверждённого потребителя/producer.

### elasticsearch
- В текущих трёх репозиториях явных интеграций не найдено.
- Пока не включать в первый рабочий staging без подтверждённого сценария использования.

---

## Сетевые правила для Kubernetes

### Внешний доступ
Снаружи должен быть доступен только:
- `api-gateway`

### Внутренний доступ
Только внутри namespace/кластера:
- `auth-service`
- `chat-service`
- `user-service`
- `postgresql`
- `redis`
- `minio`

---

## Минимальный состав первого staging

Обязательные компоненты:
- `api-gateway`
- `auth-service`
- `chat-service`
- `user-service`
- `postgresql`
- `redis`
- `minio`

Не включать в первый рабочий staging без отдельного подтверждения:
- `kafka`
- `elasticsearch`

---

## Что должно появиться дальше на основе этого файла

### Service charts
- `charts/services/api-gateway`
- `charts/services/auth-service`
- `charts/services/chat-service`
- `charts/services/user-service`

### Infra charts
- `charts/infra/postgresql`
- `charts/infra/redis`
- `charts/infra/minio`

### Environment values
- `environments/dev/values.yaml`
- `environments/staging/values.yaml`

---

## Открытые вопросы перед Helm
1. Зафиксировать единый порт `user-service`.
2. Определить окончательный формат доступа gateway -> user-service.
3. Решить, будет ли общий PostgreSQL на 3 базы или позже разнос по отдельным инстансам.
4. Добавить health probes для gRPC-сервисов.
5. Подтвердить, нужны ли `kafka` и `elasticsearch` уже сейчас, или это отдельный следующий этап.

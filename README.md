# HOW VII Mobile (Flutter)

Aplicativo mobile em **Flutter / Dart** integrado ao backend [api_mobile](https://github.com/7s3ven7/api_mobile) (.NET Web API).

## Endpoints Mapeados (`UserController` — `api/me`)

| Método | Rota | Descrição | Serviço no App |
|---|---|---|---|
| `GET` | `/api/me/safe/zone` | Retorna a lista de zonas seguras (`List<Zone>`) | `UserApiService.getSafeZones()` |
| `GET` | `/api/me/danger/zone` | Retorna a lista de zonas de perigo (`List<Zone>`) | `UserApiService.getDangerZones()` |
| `POST` | `/api/me` | Atualiza a localização do usuário | `UserApiService.updateUserLocation()` |

### Contrato de Dados (`Entities/Zone.cs` & `Entities/Position.cs`)

```json
{
  "_type_zone": "safe",
  "_position": {
    "_latitude": 48.8566,
    "_longitude": 2.3522
  },
  "_level_zone": 1,
  "_radius": 1000
}
```

## Estrutura do Projeto

```text
lib/
├── config/
│   └── api_config.dart         # Resolução automática de Base URL (10.0.2.2 no Android / localhost)
├── models/
│   ├── position_model.dart     # Mapeamento de Entities.Position (_latitude, _longitude)
│   └── zone_model.dart         # Mapeamento de Entities.Zone (_type_zone, _position, _level_zone, _radius)
├── services/
│   └── user_api_service.dart   # Cliente HTTP para GET /api/me/safe/zone, GET /api/me/danger/zone e POST /api/me
├── screens/
│   └── home_screen.dart        # Tela com Lista de Zonas, Mapa (OpenStreetMap) e envio de localização
└── main.dart                   # Entry point do app Material 3
```

## Como Rodar

1. **Suba o backend `api_mobile`**:
   ```bash
   dotnet run --project api_mobile --launch-profile http
   ```
   *(Por padrão escuta em `http://localhost:5239`)*

2. **No diretório deste projeto Flutter (`how-vii-mobile`)**, caso ainda não tenha gerado as pastas nativas (`android/`, `ios/`, `web/`):
   ```bash
   flutter create .
   flutter pub get
   flutter run
   ```

3. **Configuração de URL no App**:
   - **Emulador Android**: usa automaticamente `http://10.0.2.2:5239`
   - **Web / Desktop / Simulador iOS**: usa automaticamente `http://localhost:5239`
   - **Dispositivo Físico**: toque no ícone de rede no topo do app (`Configurar URL da API`) e informe `http://SEU_IP_LOCAL:5239`.


# Câmera dinâmica e efeitos de velocidade — definição para o RACESTARS

Definição implementada na cena e nos scripts do RACESTARS. Os valores abaixo
documentam a direção visual; o código é a referência dos ajustes finais.
A referência recebida é
textual: não foi possível comparar o resultado com o vídeo da demo.

## 1. Árvore exata da cena

Manter `game/scenes/main.tscn` como cena principal da corrida:

```text
Race (Node3D)                                      race.gd
├── WorldEnvironment
├── Sun (DirectionalLight3D)
├── Terrain (Node3D)                               terrain.gd
├── Map (Node3D)                                   map.gd
├── Player (CharacterBody3D)                       podracer.gd
│   ├── Shape (CollisionShape3D)
│   ├── Model (instância de vespa.glb)
│   │   ├── ExhaustLeft (Marker3D)
│   │   │   ├── Flame (MeshInstance3D)
│   │   │   └── Trail (CPUParticles3D)
│   │   └── ExhaustRight (Marker3D)
│   │       ├── Flame (MeshInstance3D)
│   │       └── Trail (CPUParticles3D)
│   ├── EngineLight (OmniLight3D)
│   └── SurfaceFX (Node3D)
│       ├── Dust (CPUParticles3D)
│       ├── DriftDust (CPUParticles3D)
│       ├── WaterSpray (CPUParticles3D)
│       └── Landing (CPUParticles3D)
├── CameraRig (Node3D)                             camera_rig.gd
│   └── FollowPivot (Node3D)
│       └── RotationPivot (Node3D)
│           └── SpringArm3D
│               └── Camera3D
│                   └── Wind (Node3D)
│                       ├── Left (CPUParticles3D)
│                       ├── Right (CPUParticles3D)
│                       ├── Top (CPUParticles3D)
│                       └── Bottom (CPUParticles3D)
├── SpeedFX (Node)                                 speed_fx.gd
├── Audio (Node)                                   audio.gd
├── SpeedOverlay (CanvasLayer, layer = 0)
│   └── PeripheralBlur (ColorRect)                 speed_blur.gdshader
└── HUD (CanvasLayer, layer = 1)                   hud.gd
```

O corpo físico continua sendo `Player`. A colisão, o modelo e os efeitos que
acompanham a nave ficam dentro dele. O `CameraRig` é irmão do jogador para
poder atrasar a posição e a rotação de forma independente.

Os nós de efeitos hoje são criados por código em `speed_fx.gd`. Na migração,
passam a ter os nomes/caminhos acima e deixam de ser criados uma segunda vez.
Não existe um nó `Scripts`: scripts são arquivos associados aos nós.

## 2. Responsabilidade de cada arquivo

| Arquivo em `game/` | Contrato proposto |
| --- | --- |
| `scripts/podracer.gd` | Mantém movimento, suspensão e sinais. Expõe a posição do chão encontrada pela sonda existente. |
| `scripts/speed_fx_state.gd` — novo | `RefCounted` que transporta uma amostra do estado do veículo; não é um nó e não controla a física. |
| `scripts/camera_rig.gd` | Passa de `extends Camera3D` para `extends Node3D`; controla pivôs, FOV, inclinação, primeira pessoa e impactos. |
| `scripts/speed_fx.gd` | Recebe o estado e `delta`; controla partículas, chamas, luz e overlay. Não aplica aceleração ao veículo. |
| `scripts/audio.gd` | Continua responsável pelos sons; recebe velocidade, aceleração visual e boost para modular motor/vento. |
| `scripts/race.gd` | Liga referências, coleta o estado e distribui os sinais existentes. |
| `shaders/speed_blur.gdshader` | Reutilizado para borrão periférico leve; conserva o centro e fica abaixo do HUD. |
| `shaders/exhaust.gdshader` — novo | Material unshaded aditivo, com máscara suave e pulsação discreta para as chamas. |

Interfaces da câmera: `setup(player)`, `update_state(state, delta)`, `snap()`,
`toggle()`, `shake(amount)` e `kick(amount)`. Interfaces de efeitos:
`setup(player, camera)`, `update_state(state, delta)`, `boost_flash()` e
`landing_burst(strength, state)`. `blur_enabled` continua disponível para
o sistema atual de redução automática da qualidade.

## 3. Estado compartilhado: unidades e origem dos dados

| Campo | Origem / unidade |
| --- | --- |
| `running` | `player.running`; controla se há corrida/exploração ativa. |
| `speed_mps` | `player.speed()`, velocidade horizontal em m/s. |
| `speed_ratio` | `player.speed_fraction()`, limitado a 0–1; a velocidade nominal é 125 m/s. |
| `throttle` | Comando visual 0–1: 1 quando `running && !braking`, 0 caso contrário. A nave acelera automaticamente. |
| `boost_ratio` | `clamp(player.boost / player.BOOST_MAX, 0, 1)`. `boost` original é velocidade extra em m/s. |
| `steering` | `player.steer_visual`, de −1 a 1. |
| `on_ground`, `on_water`, `drifting` | Indicadores existentes no jogador. |
| `ground_valid`, `ground_point` | Resultado da sonda central existente. |
| `ground_distance` | Distância vertical entre a origem do jogador e `ground_point`; `INF` sem chão detectado. |
| `in_tunnel` | Valor `cave` já calculado por `race.gd`. |

Não usar `velocity.length()` para os efeitos de corrida: uma queda vertical
não deve produzir vento e FOV de velocidade máxima. Não usar
`player.max_speed`, pois essa propriedade não existe neste projeto.

Trecho proposto para `podracer.gd`, reutilizando `hit` da sonda central:

```gdscript
# Campos públicos novos; não são RayCast3D adicionais.
var ground_valid := false
var ground_point := Vector3.ZERO

# Dentro de _physics_process(), imediatamente após intersect_ray(q):
ground_valid = not hit.is_empty()
if ground_valid:
    ground_point = hit.position
```

As sondas da frente e da traseira já calculam a inclinação da nave. Mantê-las
no controlador físico. Colher a amostra de efeitos depois da atualização
física do jogador; sem chão, usar `ground_distance = INF` e desligar poeira.

O núcleo da captura do estado é:

```gdscript
state.speed_mps = player.speed()
state.speed_ratio = player.speed_fraction()
state.throttle = 1.0 if player.running and not player.braking else 0.0
state.boost_ratio = clampf(player.boost / player.BOOST_MAX, 0.0, 1.0)
state.ground_distance = (
    maxf(0.0, player.global_position.y - player.ground_point.y)
    if player.ground_valid else INF
)
```

Copiar também os indicadores da tabela. A suavização é visual e não altera
os valores usados pela física. O estado compartilhado é reutilizado; não
precisa alocar um objeto novo a cada frame.

## 4. Câmera: seguimento, colisão e primeira pessoa

`FollowPivot` acompanha a posição do jogador com uma âncora 2,4 m acima da
origem. `RotationPivot` acompanha `heading` e uma fração de `visual_pitch`.
O braço se estende no eixo **+Z**; a câmera olha em **−Z**.

| Propriedade | Valor inicial proposto |
| --- | --- |
| FOV de perseguição | 72° → 88°; boost acrescenta até 5°, máximo 93°. |
| Curva de FOV | `pow(speed_ratio, 2.4)`; crescimento maior no fim da aceleração. |
| Comprimento do braço | 19 → 17 m. A escala real da Vespa pede mais que os 5–7 m do texto. |
| Inclinação vertical | −6° + `visual_pitch * 0.6`, limitada a ±25°. |
| Roll nas curvas | Até 3° no chão; atenuado no ar e na primeira pessoa. |
| Seguimento de posição / direção | Respostas exponenciais 10/s e 5/s. |
| Suavização de FOV | 5/s. |
| `SpringArm3D.collision_mask` | `1`, sólidos; excluir `player.get_rid()`. |
| `SpringArm3D.margin` | 0,30 m, maior que o deslocamento de tremor proposto. |
| `Camera3D.near` / `far` | 0,25 / 14500 m, como na cena atual. |

Manter `Camera3D` filha **direta** do `SpringArm3D`: assim o braço usa a
forma baseada no plano próximo da câmera quando não há `shape` explícita.
Um `ShakePivot` entre os dois exigiria uma forma de colisão explicitamente
configurada. O braço é o único responsável pela posição local da câmera.
O antigo código que atribui `camera.global_position` deve ser substituído
pelo seguimento dos pivôs.

Usar `h_offset`, `v_offset` e um roll pequeno para os impactos. Limitar cada
offset a ±0,08 m e usar ruído contínuo `FastNoiseLite`, em vez de sortear
uma direção a cada frame. Reduzir o tremor contínuo para 25% no ar; o impacto
de aterragem é um pulso separado. A intensidade pode ser reduzida até zero.

FOV e amortecimento independentes do FPS:

```gdscript
var factor := 1.0 - exp(-5.0 * delta)
var target_fov := 72.0 + 16.0 * pow(state.speed_ratio, 2.4)
target_fov += 5.0 * state.boost_ratio
camera.fov = lerpf(camera.fov, target_fov, factor)
impact = move_toward(impact, 0.0, 2.5 * delta)
```

Na primeira pessoa, desativar o processamento físico interno do braço com
`set_physics_process_internal(false)`, definir
`spring_length = 0` e zerar os transforms locais de `FollowPivot`,
`RotationPivot`, braço e câmera. Posicionar o rig diretamente no ponto de cabine
já usado hoje: `player.model.global_transform * Vector3(0, 2.55, 0.9)`.
Aplicar a orientação do modelo com a correção atual de −0,06 rad em X.
Usar FOV 78° → 92° e tremor menor. Ao voltar à perseguição, restaurar o
comprimento e o processamento interno do braço com
`set_physics_process_internal(true)`, zerar o transform do rig e chamar
`snap()`. `snap()` também é obrigatório
após renascer ou viajar pelo mapa: limpar os acumuladores evita que a
câmera atravesse quilômetros durante a interpolação.

Atualizar os pivôs antes do passo físico do braço, por prioridade explícita
de processamento. Não escrever o mesmo transform em `_process()` e
`_physics_process()`. A implementação deve verificar o comportamento na
primeira frame após `snap()`, antes de apresentar a imagem ao jogador.

## 5. Poeira, água, vento e propulsão

**Poeira:** `Dust` e `DriftDust` usam quad com textura radial suave,
`local_coords = false` e nenhuma sombra. Posicionar a emissão junto de
`ground_point`, com leve elevação de 0,1 m, em vez de prender as nuvens à
altura da nave. Cor inicial areia `(0.96, 0.85, 0.66)` e baixa opacidade.

```gdscript
var near_ground := state.ground_valid and state.ground_distance < 2.5
var dry_ground := state.on_ground and not state.on_water
dust.emitting = state.running and dry_ground and near_ground \
    and not state.in_tunnel and state.speed_mps > 25.0
drift_dust.emitting = dust.emitting and state.drifting
water_spray.emitting = state.running and state.on_ground \
    and state.on_water and near_ground and state.speed_mps > 25.0
```

Fade vertical: `1 - smoothstep(1.1, 2.5, ground_distance)`. Combinar com
`smoothstep(0.2, 0.8, speed_ratio)` na opacidade e na escala. No salto,
parar a emissão; deixar as partículas já lançadas terminar a vida.
`Landing` é `one_shot`, com impulso radial curto; água usa spray, nunca
poeira castanha. Uma aterragem em túnel não deve emitir poeira de areia.

**Vento:** quatro emissores presos à câmera, `local_coords = true`, gravidade
zero e direção local `(0, 0, 1)`. Distribuir caixas de emissão nas laterais,
acima e abaixo, ajustadas ao FOV/aspecto, deixando os 40% centrais livres.
Usar linhas finas de baixo alfa; aumentar velocidade e visibilidade a partir
de `smoothstep(0.60, 1.0, speed_ratio)`. Desligar durante contagem, pausa e
parado. O vento segue a câmera mesmo na primeira pessoa.

**Propulsão:** dois marcadores no modelo, em aproximadamente
`(-2.3, 1.3, -3.27)` e `(2.3, 1.3, -3.27)` no espaço local de `Model`,
conforme os bocais gerados em `blender/build_assets.py`. O modelo já tem
offset +4 m em Z; não somar esse deslocamento outra vez aos marcadores.
A chama se estende para +Z. Confirmar alinhamento no editor após importar.

Cada `Flame` pode usar dois quads cruzados com uma máscara suave; o material
aditivo desenha o núcleo e o halo sem exigir bloom. `Trail` emite no mundo
(`local_coords = false`), para deixar um rastro atrás da nave. A chama deve
seguir a inclinação visual de `Model`, e não apenas a rotação física.

```gdscript
var target_thrust := 0.0
if state.running:
    target_thrust = 0.20 + 0.65 * state.throttle + 0.35 * state.boost_ratio
thrust = lerpf(thrust, target_thrust, 1.0 - exp(-8.0 * delta))
# Aplicar thrust ao comprimento da chama, ao alfa e à luz.
# Conservar uma escala mínima positiva no mesh e escondê-lo quando apagado.
flash = move_toward(flash, 0.0, 3.0 * delta)
```

Ao travar em alta velocidade, o vento continua forte e a chama encolhe.
Usar uma única `EngineLight` sem sombras no Android. A pulsação da chama
deve ser discreta: ±5% de escala, não um piscar de tela.

**Overlay:** reutilizar o shader existente. Ativar só acima de 75% da
velocidade nominal; intensidade sugerida `0.025 * smoothstep(0.75, 1.0,
speed_ratio)`, mais até 0,01 durante boost. `mouse_filter = IGNORE`, âncoras
fullscreen e camada abaixo do HUD. Desligar no perfil baixo. Os valores
são ponto de partida visual, não uma medição de desempenho.

## 6. Ligações ao jogo existente

Separar a câmera real do controlador em `race.gd`:

```gdscript
@onready var camera_rig = $CameraRig
@onready var cam: Camera3D = $CameraRig/FollowPivot/RotationPivot/SpringArm3D/Camera3D
```

`terrain.focus`, `map.warmup()` e `fx.setup()` continuam recebendo `cam`.
As chamadas `snap`, `shake`, `kick`, `toggle`, e os campos `player` e
`first_person` passam para `camera_rig`. Manter `race.cam` apontando para
uma `Camera3D`, pois as ferramentas de captura usam seu FOV e transform.
Atualizar `tools/visual_check.gd` para parar também o controlador e o
processamento físico interno do braço antes de posicionar uma câmera de
fotografia. Apenas `set_physics_process(false)` não interrompe o passo
interno do `SpringArm3D`. Sua lista antiga de quatro
emissores deve passar a ocultar todos os novos emissores e meshes de chama;
expor essas referências em `SpeedFX` evita depender de nomes gerados.

Como `SpeedFX` e `Audio` passam a existir na cena, substituir suas criações
atuais por `preload(...).new()`/`add_child()` em `race.gd` pelas referências
`$SpeedFX` e `$Audio`. Manter apenas uma instância de cada controlador,
inclusive para não iniciar dois motores ou duas músicas ao abrir a corrida.

Reutilizar os sinais do jogador, com uma única ligação de cada sinal:

| Sinal | Reação |
| --- | --- |
| `boosted(amount)` | Som existente, pulso de chama/vento e FOV. O estado contínuo usa `boost_ratio`. |
| `landed(strength)` | Som existente, impacto de câmera e emissão curta sobre chão seco ou água. |
| `scraped(strength)` | Som e tremor existentes; sem confundir raspão com boost. |
| `crashed` | Resgate já existente; limpar efeitos transitórios e reposicionar a câmera. |

`race.gd` coordena os eventos. `SpeedFX` não chama novamente os sons já
executados pela corrida. Na pausa, câmera/efeitos usam o modo de
processamento herdado. No fim da corrida, suspender novas emissões.

## 7. Orçamento inicial por perfil

O projeto usa `gl_compatibility` tanto no PC quanto no Android. A definição
mantém `CPUParticles3D` e materiais simples; não depende de ribbon trails,
SSAO, SSIL ou névoa volumétrica. Esses recursos exigem uma avaliação
separada de renderizador e dispositivos. Bloom não é requisito da chama.

| Recurso | Android baixo | Android padrão | PC |
| --- | ---: | ---: | ---: |
| Poeira | 24 | 40 | 80 |
| Poeira de derrapagem | 12 | 20 | 40 |
| Spray, alternativo à poeira | 24 | 40 | 80 |
| Vento, total dos 4 emissores | 16 | 24 | 60 |
| Rastro por turbina | 12 | 20 | 36 |
| Aterragem, emissão pontual | 8 | 12 | 24 |
| Luz de motor, sem sombras | 0 | 1 | 1 |
| Overlay | Desligado | Leve | Leve |

Vida útil inicial: poeira 0,6–0,9 s; vento 0,2–0,35 s; rastros 0,12–0,2 s;
aterragem 0,4–0,6 s. Definir `amount` ao selecionar o perfil; não alterá-lo
continuamente, pois reinicia a emissão de `CPUParticles3D`. Modular cor,
escala e velocidade durante a corrida. Reduzir partículas por emissor
considerando o total: quatro emissores de vento dividem o orçamento.

## 8. Verificação da futura implementação

Validar no Godot e em um Android real: aceleração, travagem em alta
velocidade, boost, salto/aterragem, passagem da costa para a água, túneis,
parede atrás da câmera, troca de vista, pausa, renascimento e viagem pelo
mapa. Comparar duração de pulsos a 30 e 60 FPS. Conferir que nenhum efeito
encobre o centro/HUD e que a câmera não atravessa paredes.

A implementação tem verificação funcional em `tools/speed_fx_check.gd`.
Os pacotes da versão 0.7 incluem estas alterações; os links estão no README.

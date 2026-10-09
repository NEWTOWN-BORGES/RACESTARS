# Comandos PS4 / PS5 — 0.12

No PC, ligar o DualShock 4 ou DualSense por USB (cabo com dados), ou emparelhar por
Bluetooth nas definições do Windows. O jogo usa os mapeamentos normalizados do
Godot/SDL para comandos reconhecidos pelo sistema. Pode ligá-lo antes ou depois
de abrir o jogo. Não há seleção manual do dispositivo.

| Ação | PS4 / PS5 | Teclado |
| --- | --- | --- |
| Virar | Analógico esquerdo ou direcional | ← → ou A D |
| Travar / derrapar | L2 ou Quadrado + direção | ↓, S ou Espaço + direção |
| Recuperar a nave | Triângulo | R |
| Trocar câmera | Círculo durante a corrida | C |
| Pausar / continuar | Options | Esc |
| Navegar nos menus | Direcional ou analógico | Setas |
| Confirmar | X | Enter |
| Voltar / fechar pausa ou mapa | Círculo | Esc |

A aceleração continua automática. O analógico tem zona morta de 18% e preserva
a intensidade: mover pouco produz direção suave. Os botões direcionais e as teclas
dão direção completa. Os controlos táteis Android e o modo A15 são preservados.

Os menus mostram a opção em foco e podem ser usados sem rato. Na rede local,
abrir pausa ou mapa não para a partida; os controlos da nave ficam bloqueados com
travão para que navegar nos menus não faça a nave virar. Ao fechar, são retomados.

## Verificação

`tools/controller_check.gd`: 50 verificações usando eventos reais de entrada
sintéticos no Godot, incluindo teclas lógicas/físicas, analógico parcial/total,
centro/zona morta, direcional, gatilho e botões, toque Android, foco e navegação,
pausa e bloqueio da condução nos menus em LAN. Configurar entradas novamente
não duplica os mapeamentos.

Foram também verificados o perfil A15 e a corrida Reta do Sal. Estes testes não
substituem teste com DualShock/DualSense físico ligado a um Windows real; essa
validação não estava disponível no ambiente de desenvolvimento.

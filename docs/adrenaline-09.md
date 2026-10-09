# RACESTARS 0.9 — escala e condução

Base: v0.8. Branch: adrenaline-island. Referências: as imagens e o texto do autor,
com arquitetura monumental, florestas densas, pontes e corridas de propulsão.
As capturas são do Godot, mantendo o estilo geométrico dos modelos originais.

## Conteúdo

- Cidadela Titã: 7.194 m por volta, duas voltas, 84 m de largura, curvas de raio
  160–220 m; dois saltos com rampa de 8°, vão de 36 m e desvio lateral contínuo.
- Anel de 740 m, torres segmentadas e passadiços suspensos. Seis lotes MultiMesh;
  colisão estática do tabuleiro/barreiras. O circuito é acessível pelo menu e
  aparece como destino de viagem no mapa de exploração.
- Oito bosques em selva/floresta, 754 árvores adicionais de 60–150 m,
  com fetos, instancing, alcances limitados e menos sombras/sub-bosque no Mobile.
  A colocação exclui rotas, água, estruturas e cavernas; troncos têm colisão.
- Estrada inicial: apenas as bermas dos dois primeiros caminhos inferiores foram
  alargadas, de 68 m para até 128 m. Apoios das pontes e da estrada superior
  conservados. 16.846 células alteradas em 12 setores; centros e checkpoints iguais.
  72 objetos locais reposicionados nas margens para não flutuarem ou bloquearem a estrada.
- Física: amortecimento acompanha a velocidade vertical da rampa. Impactos nas
  paredes preservam movimento tangencial e vertical; só o componente normal ressalta.
  Os valores de aceleração, direção, velocidade máxima e derrapagem continuam iguais.

A alteração localizada da estrada e da física responde ao pedido posterior do autor;
a ilha, os restantes traçados e todos os GLBs continuam preservados.

## Verificação

- 32 testes reais de física passaram; a versão anterior falha nove dos mesmos testes.
  Hover estabiliza a 1,1 m em 30/60/120 Hz; rampa de 8° supera um vão de 45 m;
  raspão preserva 100 m/s tangenciais e separa o veículo da parede.
- 21 verificações dos sistemas visuais e 23 sondagens de oceano/túneis passaram.
- Percurso inicial alargado: passou pelos dois primeiros checkpoints em 107 s
  de simulação; centros das rotas e apoios superiores conservados.
- Cidadela Titã: duas voltas, 32/32 portões, chegada automática em 127,5 s.
- Circuito da Floresta: 18/18 portões, chegada automática em 238 s.
- Raios físicos confirmam piso, rampas, aterragens, desvios e vãos realmente abertos.
- Multiplayer: dois processos Godot na mesma máquina, contagem sincronizada,
  mais de 500 estados recebidos em cada lado e resultados de ambos recebidos.
  Não é uma validação num par de aparelhos Windows/Android reais.
- Capturas no Godot 4.6.3/Compatibility a 1280×720; sem GPU física para medir
  desempenho representativo. Não se promete o fotorrealismo das referências.

Persistem avisos de recursos no encerramento dos testes e duas texturas de ~43 KiB
no OpenGL por software, também observados na base. Não foram observados erros de
scripts ou shaders durante a execução validada.

Repetir a estrada: `python3 tools/widen_intro.py` (numpy, scipy, zstandard).
O script usa os blobs imutáveis da v0.8, é idempotente e recusa sobrescrever
alterações de mapa alheias à sua saída. Não execute make_map.py para aplicar este ajuste.

Repetir física: `godot --headless --path game --fixed-fps 120 --script ../tools/physics_check.gd`.
Repetir circuito: `godot --headless --path game --fixed-fps 60 -- --event=titan --autoplay --log --quit=160`.

[Vista geral](../screenshots/09-04-titan.png) · [Rampa](../screenshots/09-05-salto.png) · [Floresta](../screenshots/09-06-floresta.png)

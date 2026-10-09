# Nitro e câmera livre — 0.13

Segure **R2 ou X** no comando, **Shift** no teclado, ou o botão **NITRO** no ecrã.
O depósito começa a 50%, tem capacidade de 100% e permite até quatro segundos de
nitro quando cheio. A barra indica a reserva. Travar ou abrir menus interrompe o
consumo. Recuperar a nave não reabastece o depósito.

O nitro recarrega ao:

- Derrapar em movimento: recarga gradual de 8 pontos por segundo.
- Completar um salto: 8–24 pontos na aterragem, conforme o tempo no ar. É preciso
  descolar em movimento e percorrer pelo menos 15 metros; cair e recuperar não conta.
- Passar perto de um obstáculo a mais de 180 km/h sem bater: 12 pontos após passar
  o obstáculo. Há proteção contra repetir a mesma parede para acumular carga.

A velocidade continua limitada a 160 m/s. O impulso existente à saída de uma
boa derrapagem permanece. As chamas, o som de propulsão e o campo de visão usam
os efeitos já existentes; o modo A15 mantém o seu orçamento gráfico.

O **analógico direito** olha para os lados e para cima/baixo, em perseguição ou
na cabine. **R3** recentra imediatamente; no teclado, use **V**. Ao soltar o
analógico, a câmera regressa suavemente atrás da nave após 1,5 segundos. O braço
continua a evitar paredes e a recuperação limpa os ângulos antigos.

## Validação

`tools/nitro_check.gd`: 19 verificações com colisões reais em fixtures Godot:
aceleração/limite/consumo, depósito vazio e teto de carga, recuperação sem recarga,
derrapagem, passagem próxima, colisão sem prémio, salto de rampa com prémio na
aterragem, eixo direito independente, recentrar e regressar, R2, toque simultâneo
Android e consumo equivalente a 30/60/120 Hz.

Passaram também 50 verificações de comando/menu, 22 de câmera/efeitos e 18 do
perfil A15. A entrada dos comandos foi simulada; falta validação num comando
PS4/PS5 físico e no Samsung A15 real.

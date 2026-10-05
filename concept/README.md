# RACESTARS — arte conceitual

Primeiras imagens para visualizar o jogo: corrida sempre para frente no estilo **Race the Sun**,
com o visual de **Oban Star Racers** (veículos e circuitos) e mundos alienígenas tipo **Avatar**.
O foco é o mapa: um mundo bonito e caprichado para contemplar em alta velocidade.

> Todos os nomes (veículos, biomas, armas) são provisórios.

## Imagens

| # | Arquivo | O que mostra |
|---|---------|--------------|
| 1 | `images/01-canal.png` | **Canal das Ruínas (terra)**: circuito em canal no estilo Oban, torres-casulo, ponte com bandeirinhas |
| 2 | `images/02-mar.png` | **Mar dos Monólitos (mar)**: hidroplanador, calçada submersa, portal-checkpoint, duas luas, criatura gigante |
| 3 | `images/03-ceu.png` | **Arquipélago do Céu (ar)**: planador, anéis que levam ao sol, ilhas flutuantes, arraias do céu |
| 4 | `images/04-floresta.png` | **Floresta Lúmen (noite)**: moto flutuante, cogumelos gigantes e plantas bioluminescentes |
| 5 | `images/05-hangar.png` | **Hangar**: os 4 veículos com atributos, arma e habilidade |
| 6 | `images/06-gameplay.png` | **Mock-up de gameplay** no celular: obstáculos, cristais, barra do sol, turbo e arma |

## Ideias de mecânica mostradas

- Correr sempre para frente; **arrastar** para desviar.
- **Barra do sol**: a corrida acaba quando o sol se põe; **cristais de sol** recarregam a barra.
- Bônus **"QUASE!"** por passar raspando num obstáculo.
- Uma **arma** por veículo, com tempo de recarga (ex.: EMP destrói uma barreira), e um **turbo**.

## Como regenerar

As imagens são pintadas por código (Canvas 2D) e renderizadas com Chromium via Playwright.

```bash
cd src
npm i playwright   # se ainda não tiver
./render.sh        # gera tudo em ../images
```

Fontes: Nunito e Russo One (Google Fonts, licença OFL).

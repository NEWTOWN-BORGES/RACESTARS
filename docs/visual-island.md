# Validação da ilha e evolução visual

Base: `0bd6885` (versão 0.6). Verificações feitas no Godot 4.6.3 em Linux;
as capturas usam OpenGL Compatibility com Mesa/llvmpipe.

## Dados e colisões

- `python tools/island_check.py --baseline-ref 0bd6885`: passou.
- Uma ilha contínua, 26,7% da área de dados coberta pelo mar, 16 regiões preservadas.
- 86 traçados iguais à base; diferença máxima de altura de 1 cm num ponto arredondado.
- A geração verificou 513.447 amostras de centros e margens das pistas: alteração zero pela costa.
- Portões, túneis, pontes e aquedutos preservados; zero problemas no verificador do gerador.
- 270 retângulos de colisão do oceano, sem interseção com as rotas; 134.585 plantas fora de água.
- `tools/island_runtime_check.gd`: 23 verificações reais de física passaram — seis posições do mar
  com superfície em y=0 e 17 túneis subterrâneos com chão seco.
- `python tools/vegetation_check.py --compare-ref 0bd6885`: passou. As quatro árvores mantêm as
  dimensões e cores dos vértices; geometria entre 1,39 e 1,43 vezes a original.

## Corridas com piloto automático

| Prova | Resultado | Reposicionamentos automáticos |
|---|---|---|
| Reta do Sal | Terminou em 27,7 s | 0 |
| Circuito da Floresta | 18/18 portões, terminou em 240,6 s | 0 |
| Circuito dos Monumentos | 18/18 portões, terminou em 198,4 s | 0 |
| Grande Corrida, variante 0 | 30/30 portões, terminou em 1134,2 s | 3 |
| Grande Corrida da base 0.6, variante 0 | 30/30 portões, terminou em 1138,3 s | 7 |

A corrida longa confirma conclusão, mas não é uma passagem sem assistência: o mecanismo de
teste avança o piloto quando este fica preso. Dois bloqueios repetem locais da versão base;
o terceiro ocorreu na zona da floresta. Nem todas as combinações de caminhos foram percorridas.
Algumas execuções headless aceleradas emitiram avisos de recursos de áudio ao fechar; a
investigação identificou streams de áudio existentes, sem erro de geometria ou shader.

## Imagens e limites

`tools/visual_check.gd` produziu capturas reais do Porto do Sol, Farol das Marés e Santuário do
Cenote, guardadas em `screenshots/16-porto-da-ilha.png`, `17-costa-da-ilha.png` e
`18-santuario-da-ilha.png`. A importação final e a renderização concluíram sem erros de script
ou compilação de shaders.

O desempenho e a compatibilidade num aparelho Android ainda não foram medidos. O APK
versionado continua a ser o da versão 0.6; nenhum APK novo foi produzido nesta alteração.

# Física e recuperação — 0.11

A água tinha caixas sólidas: as laterais das margens e das peças do oceano podiam
barrar a nave. Agora são superfícies de apoio apenas, sem colisão lateral com o
casco ou com a câmera. A suspensão impede atravessar a água numa aterragem rápida.

A nave mede a normal da superfície no centro e nas extremidades. O casco acompanha
encostas e antecipa a orientação numa aterragem; o modelo segue a inclinação e a
trajetória com molas amortecidas. Gravidade tangencial reduz o embalo nas subidas e
acelera nas descidas. O controlo lateral no ar é menor. Bordas sem apoio libertam
a nave para o salto; paredes verticais e tetos não são superfícies de flutuação.

A câmera acompanha subida/descida, inclina ligeiramente nas curvas e amortece
impulsos de salto e aterragem. O SpringArm continua a resolver obstáculos. A
primeira pessoa permanece ancorada à cabine e o reposicionamento limpa os impulsos.

## Se ficar preso

Toque **RECUPERAR**, ou pressione **R** no PC. Depois de seis segundos sem avançar,
a recuperação também atua automaticamente, salvo se estiver a travar. O jogo
confere apoio sob a nave e espaço livre para o casco; usa uma posição anterior
segura ou recua para um checkpoint validado. Tempo e checkpoints não são reiniciados.
Soltar o dedo sobre um botão também termina o comando de direção/travão.

## Validação

- `tools/physics_check.gd`: 32 verificações de aterragem a 30/60/120 Hz, raspão,
  colisão frontal, queda junto a parede, rampa e salto de 45 metros.
- `tools/handling_check.gd`: 46 verificações; subidas/descidas de 30° a três taxas,
  transições de 15° e 40°, inclinação lateral, borda de abismo, parede vertical,
  teto baixo, margem de água, aterragem na água a 95 m/s, espaços de recuperação
  e libertação do toque sobre HUD.
- `tools/recovery_check.gd`: 7 verificações no mapa real. Recuperação automática e
  manual preservam o cronómetro e os checkpoints; travar não dispara recuperação.
  62 de 63 largadas/portões têm apoio livre diretamente. Um portão bloqueado recua
  para um candidato anterior validado.
- `tools/speed_fx_check.gd`: 22 verificações, incluindo colisão da câmera, primeira
  pessoa, mudança de câmera, declives e mola independente da taxa de atualização.
- `tools/stable_profile_check.gd`: 18 verificações; perfil A15 preservado.
- `tools/visual_system_check.gd`: 21 verificações; quatro perfis e sistemas visuais.
- Provas reais em execução: Reta do Sal terminada pelo piloto automático em 27,7 s;
  65 s simulados da Grande Corrida e Cidadela Titã sem erros de script/física.
- Captura real com o renderizador Compatibility para conferir o botão RECUPERAR.

São testes de simulação e integração no Godot 4.6.3. Não representam teste físico
num Samsung A15 nem cobertura de todos os locais possíveis nos 24 km do mapa.
O modo **Gráficos: A15 (30 FPS)** continua no APK, com física a 60 Hz, resolução
adaptativa e orçamentos reduzidos. Nenhum novo efeito gráfico pesado foi introduzido.

# Sistemas visuais implementados

A cena mantém a ilha e as regras de condução. `EnvironmentSystem` controla
iluminação, reflexos locais e névoa; `GlobalVFX` cria poeira ambiente;
`SurfaceWear` acrescenta marcas discretas de desgaste junto dos monumentos.
O céu procedural com planeta/anéis fornece ambiente e reflexos, preservando
a identidade existente sem baixar um HDRI externo.

No menu inicial, **Gráficos: Leve / Equilibrado / Alto** grava a preferência
para as próximas corridas. Também é possível testar com `--quality=mobile`,
`--quality=balanced` ou `--quality=ultra` depois de `--`.

| Recurso | Leve | Equilibrado | Alto |
| --- | --- | --- | --- |
| Partículas ambientais | 16 | 36 | 64 |
| Reflexos locais | Céu | 2 probes estáticas | 2 probes estáticas |
| Sombras, distância | 120 m | 220 m | 300 m |
| Antialiasing | 2× | 2× | 4× |
| Glow | Desligado | Suave, se suportado | Suave, se suportado |
| SSAO | Desligado | Forward+ | Forward+ |
| SSIL e névoa volumétrica | Desligados | Desligados | Forward+ |

O projeto continua a iniciar em Compatibility. Selecionar Alto não troca
o renderizador durante a execução. Num PC com Vulkan suportado, iniciar
com `godot --path game --rendering-method gl_compatibility` mantém o modo
testado; `--rendering-method forward_plus` habilita os recursos específicos
de Forward+. Esse segundo caminho precisa de avaliação visual e de
desempenho no dispositivo alvo. Glow em Compatibility é condicionado ao
Godot 4.6 ou posterior; os outros recursos avançados usam a capacidade do
renderizador, não apenas o nome do perfil.

Os materiais da nave distinguem pintura, metal e superfícies escuras usando
as cores existentes do modelo; os detalhes pequenos desaparecem à distância
para reduzir cintilação. As superfícies emissivas originais são preservadas.
Props recuperam reflexos especulares com rugosidade alta; rocha, terreno e
vegetação mantêm os seus shaders próprios. As marcas no chão usam malha
conformada, compatível com o Android, em vez de depender de `Decal`.

A câmera, partículas de corrida e propulsão estão descritas em
[camera-speed-fx.md](camera-speed-fx.md). O impulso tem uma separação
cromática discreta apenas nas bordas. O centro e o HUD permanecem legíveis.

Verificação:

```sh
godot --headless --path game --script ../tools/speed_fx_check.gd
godot --headless --path game --script ../tools/visual_system_check.gd
godot --headless --path game --audio-driver Dummy --fixed-fps 60 -- --event=drag --autoplay --log --quit=38
```

Os testes verificam efeitos de terra/água/ar, travagem, duração do boost,
colisão da câmera, primeira pessoa, viagem, pausa e limites dos perfis.
A corrida Reta do Sal terminou em 27,7 s no teste automático. A visualização
foi conferida no Godot 4.6.3 / OpenGL Compatibility com renderização por
software. Isso não mede FPS de um telefone. Os pacotes Android/Windows 0.7
foram exportados posteriormente; os links estão no README.

Resultado final: 17 verificações de câmera/efeitos e 18 verificações do
sistema visual passaram. Capturas do menu e das duas vistas foram conferidas.
Na saída do render OpenGL/llvmpipe ainda aparecem avisos de duas texturas
não libertadas (aproximadamente 43 KiB no total), mesmo após libertar a cena
antes de encerrar. A origem desse aviso de limpeza não foi isolada; não
aparecem erros de script ou de compilação de shader nas capturas finais.

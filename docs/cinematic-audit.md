# Auditoria para a evolução cinematográfica

Base preservada: **v0.7**, commit `81f3094`. Esta auditoria prepara a nova
direção visual; não altera o jogo. As cinco novas referências e o restante
da fase 6 ainda serão indicados pelo autor.

| Sistema | Implementação atual | Orientação para a próxima alteração |
| --- | --- | --- |
| Geografia e biomas | `tools/make_map.py`, `tools/island.py`; dados em `game/assets/map`; `terrain.gd` e `map.gd` carregam o mundo | Não regenerar nem modificar heightmap, rotas, checkpoints, colisões ou costa. Trabalhar nos materiais. |
| Terreno | `terrain.gdshader`, mapa de biomas, malhas de terreno por setores | Melhorar transições de materiais, escala de detalhe e leitura de encostas mantendo vértices e alturas. |
| Rocha e montanhas | `rock.gdshader`, `rock_far.gdshader`, `rock_common.gdshaderinc`; variação por bioma, estratos e detalhe procedural | Refinar contraste, rugosidade e desgaste; conservar o detalhe reduzido à distância para evitar cintilação. |
| Pontes, túneis e monumentos | GLBs `ponte_*`, `tunel_*`, `piramide`, `obelisco`, `arch_*`, `colosso_*`; gerados originalmente em `blender/build_assets.py` | Preservar todos os GLBs e volumes de colisão. Camadas de desgaste/musgo podem ser materiais ou complementos visuais sem colisão. |
| Cenários da ilha | `island_scenery.gd`: 12 conjuntos; materiais de pedra, bandeiras e aves; `surface_wear.gd` | Integrar a paleta das referências sem mover estruturas nem invadir trajetórias. Emissão reservada à tecnologia. |
| Natureza | Árvores, arbustos, palmeiras, fetos e cobertura em GLBs/MultiMesh; `foliage.gdshader` anima vento | Melhorar materiais/contexto de vegetação; não substituir modelos nem remover instancing. |
| Água | `water.gdshader` para lagos; `ocean.gdshader`, máscara costeira e altura do terreno para mar/espuma | Ajustar profundidade, cor e reflexos sem alterar superfície física, nível de água ou túneis secos. Spray já distingue água de solo. |
| Iluminação e atmosfera | `environment_controller.gd`, `environment.tres`, céu procedural com planeta/anéis; `global_vfx.gd` | Manter o controlador existente. Adaptar cor/exposição/nevoeiro às referências, verificando legibilidade de pistas e nave. |
| Veículos | `model_materials.gd`, `vehicle_surface.gdshader`, materiais emissivos do modelo, `exhaust.gdshader` | Refinar pintura/metal/rugosidade e energia; não editar GLBs, suspensão, aceleração, travagem ou direção. |
| Câmera e velocidade | `camera_rig.gd`, `speed_fx_state.gd`, `speed_fx.gd`, `audio.gd` | Reutilizar o estado compartilhado e os eventos de boost/aterragem. Manter colisão de câmera e primeira pessoa. |

## Desempenho e perfis

O terreno tem cinco passos de LOD (1, 2, 4, 8, 16), com transições por
distância. Props/vegetação usam MultiMesh agrupados em células de 1 km e
alcances de visibilidade específicos; estruturas colossais continuam
visíveis a distâncias maiores. Isso deve ser preservado: acrescentar
detalhe em cada instância individual destruiria parte desse benefício.

Os perfis atuais são **Leve, Equilibrado e Alto**, persistidos por
`visual_quality.gd`. Controlam partículas, reflexos, sombras e MSAA.
Compatibility continua sendo o renderizador padrão no PC e no Android.
SSAO/SSIL/volumetria são condicionados a Forward+; não devem ser usados
como base obrigatória da nova aparência. Glow em Compatibility depende de
Godot 4.6+. Os limites atuais estão em `visual-systems.md`.

Há dois avisos de limpeza de textura na saída do renderer OpenGL por
software; estão documentados e não devem ser confundidos com validação
em um telefone. O desempenho real de Android/Windows ainda precisa ser
medido nos dispositivos alvo.

## Critérios de preservação

Comparar a futura alteração com a tag `v0.7`: arquivos de dados do mapa e
GLBs devem permanecer idênticos. Alterações de scripts devem se limitar à
apresentação. Verificar as vistas de perseguição/primeira pessoa, os três
perfis, solo/água/túnel e a legibilidade dos checkpoints. Reutilizar os
testes de câmera/efeitos e de perfis, além de uma corrida com os dados
exportados. Capturas comparáveis devem usar posição, orientação e horário
de iluminação iguais.

As fases de implementação artística dependem das novas referências e da
conclusão do pedido, conforme indicado pelo autor na conversa.

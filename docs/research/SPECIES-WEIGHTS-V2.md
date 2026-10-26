# 100 种鸟全国综合体验：初始权重与研究证据

研究日期：2026-10-26。状态：**权重已应用到 macOS 目录及共享资源镜像，用户真实配置未修改**。研究数据仍保留提案时的目录基线用于溯源。机制与迁移详见[概率系统 V2 完整方案](../PROBABILITY-SYSTEM-V2-PLAN.md)；可编程读取的完整数据见 [species-weights-v2.json](species-weights-v2.json)。

## 1. 调研口径与能回答的问题

对象为当前目录的 100 个物种 ID，而不是中国全部鸟种；按学名与资料条目对齐。用户选择全国综合体验，故覆盖现有台湾、西北、高原与沿海鸟种，采用全年综合视角。所有提案条目作为系统默认权重，数值均为正；不设置逐鸟启用开关。默认隐藏调整表，只有勾选“手动调整概率”才显示并应用手动覆盖值；“重置为系统默认值”清空覆盖值并取消勾选。

没有可直接查得、适用于所有地区和季节的“全国每种鸟出现百分比”。本次查阅了全部 100 个对应的生物多样性知识平台条目，提取来源学名、分布/生境及其记录的 IUCN 标签；对分类或状态冲突辅以香港观鸟会、CMS 等资料，并用官方名录逐项核对保护标记。来源支持定性判断，具体权重由产品设计决定，未作全国观测数据统计拟合。

eBird 方法把遇见率定义在标准化清单上，地区、季节和观察努力会影响结果，不能把单地计数或全体原始记录占比直接当作全国概率。[方法来源][ebirdMethod]

已有目录 weightBasis 提及中国鸟类观察年报。本次检索的 2025 年报转述发表于 2026 年，不能混同观察年与发布日期；未获得可复算的全国标准清单和完整计算口径，转述文本亦存在名单表述矛盾，所以不据此生成数值排名，也不宣称本表权重由年报统计得到。[转述线索][annualRepost]

## 2. 七档设计规则

先判断国内分布范围、适宜地区常见程度、生境与季节限制，再给地方常见鸟保留区域代表性。以下是人工分档指南，不是生态风险等级，也不把不同维度硬凑成未经校准的科学评分公式。每种鸟的最终裁量理由列在第 4 节。

| 权重 | 数量 | 全候选时单种占比 | 设计用途 |
|---:|---:|---:|---|
| 120 | 5 | 2.2396% | 日常体验基准；广布或中东部/南方极常见且贴近生活 |
| 90 | 10 | 1.6797% | 广布常见，或多地常见的水鸟、候鸟 |
| 65 | 31 | 1.2131% | 多地或大区域常见，作为常规出现主体 |
| 45 | 25 | 0.8399% | 地区常见或有明显生境/季节条件，保留中频 |
| 30 | 19 | 0.5599% | 地域特色、季节性或中低频；给当地常见鸟代表份额 |
| 18 | 6 | 0.3359% | 相对少遇见、隐蔽或地域集中；低频但可遇见 |
| 10 | 4 | 0.1866% | 特别体验最低档；不代表都濒危或法律等级最高 |

总权重 **5358**，没有“合计必须 100”的要求。最高/最低单种相对频率为 12:1；原新增 54 种的合计基础份额为 **48.04%**。这些百分比仅在所有 100 种均使用本表系统默认权重、都满足本次选择条件且上下文系数为 1 时成立；手动修改权重（包括设为 0）或进入群飞子集后重新计算。

修正旧预设的几个例子：台湾拟啄木鸟在台湾当地常见、地山雀在高原地区局部常见，因此均设为 30；特有种银喉长尾山雀设为 65。不能将分布范围较小等同于当地稀有。[台湾拟啄木鸟][cern:taiwanBarbet] [地山雀][cern:groundTit] [银喉长尾山雀][cern:silverThroatedBushtit]

同为国家二级保护，高山兀鹫设为 10、红隼设为 30、黑鸢和褐翅鸦鹃设为 45，原因是分布、生境和体验分档不同；国家等级本身没有乘数。高山兀鹫的来源记录为 NT（近危），与中国二级保护是两个不同体系。[官方名录][nationalTable] [CMS][cmsVulture]

## 3. 保护与分类信息如何阅读

- **来源LC / 来源NT**：所查资料记载的 IUCN 标签；LC=无危，NT=近危。未逐种取得 IUCN 最新独立评估年份，JSON 的 assessmentYear 保留 null、latestIndependentAssessmentVerified=false；不能称为“2026 年逐种最新评估已确认”。
- **NR／LC\***：大山雀和牛背鹭的 CERN 条目标 NR，补充来源出现 LC，且涉及广义分类口径；NR 是来源原文，不转换为正式的 NE 或 DD。
- **LC\*（分类口径）**：黄腹花蜜鸟的新旧分类边界存在差异。旧种或广义种的状态不直接等于拆分种的独立评估。
- **国家Ⅱ**：2021 年国家重点保护名录核对到的二级条目；本表 11 种，无国家一级条目。
- **三有**：2023 年《有重要生态、科学、社会价值的陆生野生动物名录》匹配，含同中文名的属名/异名差异记录，共 82 种；三有不叫“国家三级”。
- **三有映射待核**：5 种存在拆分分类与法定条目对应问题，列出官方原名称，但不把对应关系说成已确认。
- **两名录未匹配**：大嘴乌鸦、小嘴乌鸦未匹配本次核对的两份名录；不能据此推断“没有任何保护”。本表未逐一汇编地方、地区及其他法规名录。

官方口径使用 2021 年第 3 号公告与 2023 年第 17 号公告；2026 年 7 月国家林草局发布会仍引用这两次调整。三有全文 PDF 地址含 202605 是托管路径，不代表 2026 年新修订。[重点名录公告][national2021] [三有公告][three2023] [全文 PDF][threePDF] [2026 发布会][official2026]

## 4. 全部 100 种的提案

“理由”一列将来源支持的分布/常见性与本次设计决定合写；所有数字均为人工设计值。行号 47–100 是原扩展新增的 54 种。各行物种链接支持定性依据和来源 IUCN 标签；保护列分别链接官方名录，分类问题详见第 5 节。稳定 ID 与各项元数据保存在配套 JSON。

| # / 鸟种 | 学名（本表采用） | 权重 | 入场占比 | IUCN来源记录 | 名录核对 | 分档理由与物种来源 |
|---|---|---:|---:|---|---|---|
| 1. 红耳鹎 | Pycnonotus jocosus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 华南低海拔公园、庭院和灌丛常见；作为南方日常鸟，提升到中高频。 [物种][cern:redWhiskeredBulbul] |
| 2. 麻雀 | Passer montanus | 120 | 2.2396% | 来源LC | [三有][threePDF] | 国内分布广、适应城镇与农田；全国日常体验的最高频基准。 [物种][cern:treeSparrow] |
| 3. 白头鹎 | Pycnonotus sinensis | 120 | 2.2396% | 来源LC | [三有][threePDF] | 中东部与南方常见，适应公园及居民区；设为日常高频基准。 [物种][cern:lightVentedBulbul] |
| 4. 珠颈斑鸠 | Spilopelia chinensis | 120 | 2.2396% | 来源LC | [三有][threePDF] | 中东部及南方开阔地、村庄常见；设为日常高频基准。 [物种][cern:spottedDove] |
| 5. 乌鸫 | Turdus mandarinus | 90 | 1.6797% | 来源LC | [三有][threePDF] | 中东部广布且常见；保持高频，但不给单一熟悉鸟过高份额。 [物种][cern:chineseBlackbird] |
| 6. 鹊鸲 | Copsychus saularis | 65 | 1.2131% | 来源LC | [三有][threePDF] | 南方常见留鸟；保留高于特色山地鸟的出现频率。 [物种][cern:magpieRobin] |
| 7. 棕背伯劳 | Lanius schach | 65 | 1.2131% | 来源LC | [三有][threePDF] | 中东部和南方低海拔开阔地常见；列入中高频常见鸟。 [物种][cern:longTailedShrike] |
| 8. 夜鹭 | Nycticorax nycticorax | 65 | 1.2131% | 来源LC | [三有][threePDF] | 适宜湿地分布广、较易遇见；按湿地常见鸟设置中高频。 [物种][cern:nightHeron] |
| 9. 红尾水鸲 | Phoenicurus fuliginosus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 山地溪流中常见，但依赖水流生境；提高区域代表性而非按全国罕见处理。 [物种][cern:plumbeousWaterRedstart] |
| 10. 白鹭 | Egretta garzetta | 90 | 1.6797% | 来源LC | [三有][threePDF] | 南方及东部适宜湿地常见；设为高频湿地代表鸟。 [物种][cern:littleEgret] |
| 11. 苍鹭 | Ardea cinerea | 90 | 1.6797% | 来源LC | [三有][threePDF] | 全国适宜湿地广布，部分种群迁徙；保持高频。 [物种][cern:greyHeron] |
| 12. 红隼 | Falco tinnunculus | 30 | 0.5599% | 来源LC | [国家Ⅱ][nationalTable] | 国内较常见的猛禽，开阔地可见；与普通小型鸟拉开频率，保护等级不作扣分。 [物种][cern:commonKestrel] |
| 13. 游隼 | Falco peregrinus | 10 | 0.1866% | 来源LC | [国家Ⅱ][nationalTable] | 分布广但国内总体不常见；设特色低频，仍保留正权重。 [物种][cern:peregrineFalcon] |
| 14. 黑鸢 | Milvus migrans | 45 | 0.8399% | 来源LC | [国家Ⅱ][nationalTable] | 国内部分种群广布常见；不能仅因是猛禽或二级保护而压到最低档。 [物种][cern:blackKite] |
| 15. 普通鵟 | Buteo japonicus | 30 | 0.5599% | 来源LC | [国家Ⅱ][nationalTable] | 东北繁殖、南方越冬；以季节性猛禽体验设中低频，分类名称另行核对。 [物种][cern:commonBuzzard] |
| 16. 喜鹊 | Pica serica | 120 | 2.2396% | 来源LC | [三有映射待核][threePDF] | 中东部及南方广布常见；设为日常高频基准，与欧亚喜鹊保留两个ID。 [物种][cern:orientalMagpie] |
| 17. 灰喜鹊 | Cyanopica cyanus | 90 | 1.6797% | 来源LC | [三有][threePDF] | 华北、东北和华东多地常见；保持高频区域常见鸟地位。 [物种][cern:azureWingedMagpie] |
| 18. 大嘴乌鸦 | Corvus macrorhynchos | 65 | 1.2131% | 来源LC | [两名录未匹配][threePDF] | 国内大部分适宜地区常见；提高旧预设中偏低的相对优先级。 [物种][cern:largeBilledCrow] |
| 19. 戴胜 | Upupa epops | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内大部分中低海拔地区有分布，较常见；作为开阔地代表鸟设中高频。 [物种][cern:hoopoe] |
| 20. 家燕 | Hirundo rustica | 90 | 1.6797% | 来源LC | [三有][threePDF] | 繁殖期遍及国内大部地区；全国全年综合仍高频，不模拟严格冬季屏蔽。 [物种][cern:barnSwallow] |
| 21. 绿头鸭 | Anas platyrhynchos | 90 | 1.6797% | 来源LC | [三有][threePDF] | 国内常见水鸟，北方繁殖、部分种群南迁；高频湿地代表。 [物种][cern:mallard] |
| 22. 噪鹃 | Eudynamys scolopaceus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 国内南方为主，多地为夏候鸟；考虑季节性设置中频。 [物种][cern:asianKoel] |
| 23. 暗绿绣眼鸟 | Zosterops simplex | 65 | 1.2131% | 来源LC | [三有映射待核][threePDF] | 中东部及南方林缘、公园常见；设中高频，名录旧分类另标注。 [物种][cern:swinhoesWhiteEye] |
| 24. 红嘴鸥 | Chroicocephalus ridibundus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 迁徙和越冬期在湖河及海岸常见；提高季节性常见水鸟的可见度。 [物种][cern:blackHeadedGull] |
| 25. 中杓鹬 | Numenius phaeopus | 30 | 0.5599% | 来源LC | [三有][threePDF] | 沿海迁徙期可局部常见，但依赖潮滩和季节；不再因内陆少见置于最低档。 [物种][cern:whimbrel] |
| 26. 斑鱼狗 | Ceryle rudis | 18 | 0.3359% | 来源LC | [三有][threePDF] | 中南部水域分布，资料描述为偶见；设置低频水鸟特色。 [物种][cern:piedKingfisher] |
| 27. 丘鹬 | Scolopax rusticola | 10 | 0.1866% | 来源LC | [三有][threePDF] | 迁徙可经过多地，繁殖记录较少且活动隐蔽；采用低频体验。 [物种][cern:eurasianWoodcock] |
| 28. 黑卷尾 | Dicrurus macrocercus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内多地低海拔开阔地常见，部分为候鸟；设中高频。 [物种][cern:blackDrongo] |
| 29. 池鹭 | Ardeola bacchus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 东部湿地和农田常见，西部较少；设中高频湿地代表。 [物种][cern:chinesePondHeron] |
| 30. 白眉姬鹟 | Ficedula zanthopygia | 30 | 0.5599% | 来源LC | [三有][threePDF] | 北部和中东部繁殖、南方迁徙过境；按季节性林鸟设中低频。 [物种][cern:yellowRumpedFlycatcher] |
| 31. 黄眉柳莺 | Phylloscopus inornatus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 除西北外多地迁徙林地常见；保留迁徙小鸟的中高频体验。 [物种][cern:yellowBrowedWarbler] |
| 32. 大山雀 | Parus minor | 90 | 1.6797% | NR／LC* | [三有映射待核][threePDF] | 按目录Parus minor识别为远东山雀，中东部各类林地常见；高频，避免与Parus major混合。 [物种][cern:greatTit] [补证][hkTit] |
| 33. 黑水鸡 | Gallinula chloropus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 多数地区适宜淡水湿地常见；设置中高频。 [物种][cern:commonMoorhen] |
| 34. 大斑啄木鸟 | Dendrocopos major | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内分布较广的啄木鸟，林地及园林可见；设置中高频。 [物种][cern:greatSpottedWoodpecker] |
| 35. 棕头鸦雀 | Sinosuthora webbiana | 65 | 1.2131% | 来源LC | [三有][threePDF] | 多地灌丛、林缘常见留鸟；设置中高频。 [物种][cern:vinousThroatedParrotbill] |
| 36. 黑翅长脚鹬 | Himantopus himantopus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 适宜湿地常见且具有迁徙性；设置中频。 [物种][cern:blackWingedStilt] |
| 37. 白骨顶 | Fulica atra | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内多数地区适宜湖泊常见，南北季节流动；设置中高频。 [物种][cern:eurasianCoot] |
| 38. 红嘴相思鸟 | Leiothrix lutea | 30 | 0.5599% | 来源LC | [国家Ⅱ][nationalTable] | 中南部和西南山林分布，作为林下特色鸟设中低频；不因二级保护直接设最低档。 [物种][cern:redBilledLeiothrix] |
| 39. 黑领椋鸟 | Gracupica nigricollis | 65 | 1.2131% | 来源LC | [三有][threePDF] | 长江以南多地常见留鸟；提高南方区域常见鸟代表性。 [物种][cern:blackCollaredStarling] |
| 40. 普通翠鸟 | Alcedo atthis | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内多数低海拔适宜水域常见；设中高频，保护元数据以官方名录为准。 [物种][cern:commonKingfisher] |
| 41. 金眶鸻 | Charadrius dubius | 45 | 0.8399% | 来源LC | [三有][threePDF] | 国内多地淡水湿地分布，有季节差异；设中频。 [物种][cern:littleRingedPlover] |
| 42. 黑尾蜡嘴雀 | Eophona migratoria | 45 | 0.8399% | 来源LC | [三有][threePDF] | 东北繁殖及中东部部分地区常见，季节迁移明显；设中频。 [物种][cern:yellowBilledGrosbeak] |
| 43. 红胁蓝尾鸲 | Tarsiger cyanurus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 东北繁殖、南方越冬；设中频季节性林鸟。 [物种][cern:redFlankedBluetail] |
| 44. 领角鸮 | Otus lettia | 18 | 0.3359% | 来源LC | [国家Ⅱ][nationalTable] | 南方林地乃至城郊可见，夜行降低日常遇见机会；低频但不标成现实稀有。 [物种][cern:collaredScopsOwl] |
| 45. 斑头鸺鹠 | Glaucidium cuculoides | 18 | 0.3359% | 来源LC | [国家Ⅱ][nationalTable] | 南方丘陵并非罕见；特色鸮类设低频，保留可遇见性。 [物种][cern:asianBarredOwlet] |
| 46. 纵纹腹小鸮 | Athene noctua | 30 | 0.5599% | 来源LC | [国家Ⅱ][nationalTable] | 国内北部和西部多地常见；提高区域代表性，不把所有鸮类设同一最低档。 [物种][cern:littleOwl] |
| 47. 丝光椋鸟 | Spodiopsar sericeus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 中东部及南方多地常见；提高旧预设相对份额。 [物种][cern:silkyStarling] |
| 48. 八哥 | Acridotheres cristatellus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 黄河以南多地常见留鸟；设中高频，以野生分布为依据。 [物种][cern:crestedMyna] |
| 49. 凤头䴙䴘 | Podiceps cristatus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 较大湖泊地区性常见，南北季节迁移；设中频。 [物种][cern:greatCrestedGrebe] |
| 50. 北红尾鸲 | Phoenicurus auroreus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内多地较常见，繁殖与越冬区不同；设中高频。 [物种][cern:daurianRedstart] |
| 51. 台湾拟啄木鸟 | Psilopogon nuchalis | 30 | 0.5599% | 来源LC | [三有][threePDF] | 台湾特有且当地森林、公园常见；给区域代表性额度，不按全国范围小直接判罕见。 [物种][cern:taiwanBarbet] |
| 52. 地山雀 | Pseudopodoces humilis | 30 | 0.5599% | 来源LC | [三有][threePDF] | 青藏高原及邻近地区局部常见；给高原代表性额度。 [物种][cern:groundTit] |
| 53. 大白鹭 | Ardea alba | 65 | 1.2131% | 来源LC | [三有][threePDF] | 适宜湿地地区性常见，部分种群迁徙；设中高频。 [物种][cern:greatEgret] |
| 54. 大鵟 | Buteo hemilasius | 30 | 0.5599% | 来源LC | [国家Ⅱ][nationalTable] | 北方和高原适宜地区常见、南方较少；给北方猛禽中低频份额。 [物种][cern:uplandBuzzard] |
| 55. 小䴙䴘 | Tachybaptus ruficollis | 90 | 1.6797% | 来源LC | [三有][threePDF] | 国内多地淡水水域普遍常见；设高频。 [物种][cern:littleGrebe] |
| 56. 小嘴乌鸦 | Corvus corone | 45 | 0.8399% | 来源LC | [两名录未匹配][threePDF] | 华北、华中等地繁殖，部分冬季南迁；作为北方常见鸦类设中频。 [物种][cern:carrionCrow] |
| 57. 山噪鹛 | Pterorhinus davidi | 18 | 0.3359% | 来源LC | [三有][threePDF] | 北部和中部特有山地灌丛鸟，资料记为偶见；设低频特色。 [物种][cern:plainLaughingthrush] |
| 58. 山斑鸠 | Streptopelia orientalis | 90 | 1.6797% | 来源LC | [三有][threePDF] | 全国多地广布常见，部分为候鸟；设高频。 [物种][cern:orientalTurtleDove] |
| 59. 斑嘴鸭 | Anas zonorhyncha | 90 | 1.6797% | 来源LC | [三有][threePDF] | 国内常见水鸟，南北季节迁移；设高频。 [物种][cern:easternSpotBilledDuck] |
| 60. 普通䴓 | Sitta europaea | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内多地林地常见；提高旧预设相对份额。 [物种][cern:eurasianNuthatch] |
| 61. 棕胸岩鹨 | Prunella strophiata | 10 | 0.1866% | 来源LC | [三有][threePDF] | 西部高海拔山地分布且资料记为不常见；设低频特色。 [物种][cern:rufousBreastedAccentor] |
| 62. 欧亚喜鹊 | Pica pica | 30 | 0.5599% | 来源LC | [三有][threePDF] | 国内北部和西部的区域代表；给中低频份额，与喜鹊分别保留。 [物种][cern:eurasianMagpie] |
| 63. 欧亚大山雀 | Parus major | 30 | 0.5599% | 来源LC | [三有][threePDF] | 国内西北和极东北适宜地区常见；给区域代表性额度，勿误认作大山雀同一条目。 [物种][cern:eurasianGreatTit] |
| 64. 沼泽山雀 | Poecile palustris | 45 | 0.8399% | 来源LC | [三有][threePDF] | 东北及部分中东部、西南林地常见，分布不连续；设中频。 [物种][cern:marshTit] |
| 65. 灰卷尾 | Dicrurus leucophaeus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 多地丘陵、林缘常见，部分为候鸟；设中频。 [物种][cern:ashyDrongo] |
| 66. 灰斑鸠 | Streptopelia decaocto | 65 | 1.2131% | 来源LC | [三有][threePDF] | 北方及西部常见、东南较少；全国预设应保留中高频。 [物种][cern:eurasianCollaredDove] |
| 67. 灰树鹊 | Dendrocitta formosae | 45 | 0.8399% | 来源LC | [三有][threePDF] | 东南及南方丘陵森林局部常见；设中频。 [物种][cern:greyTreepie] |
| 68. 灰椋鸟 | Spodiopsar cineraceus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 北方繁殖、黄河以南多为越冬；设中高频季节性常见鸟。 [物种][cern:whiteCheekedStarling] |
| 69. 灰腹噪鹛 | Trochalopteron henrici | 18 | 0.3359% | 来源LC | [三有][threePDF] | 西藏南部和东南部山地局部常见；保留地域代表性，不因分布窄设最低档。 [物种][cern:henricsLaughingthrush] |
| 70. 灰腹绣眼鸟 | Zosterops palpebrosus | 30 | 0.5599% | 来源LC | [三有][threePDF] | 西南和华南西部适宜丘陵常见；设中低频区域代表。 [物种][cern:indianWhiteEye] |
| 71. 牛背鹭 | Bubulcus coromandus | 65 | 1.2131% | NR／LC* | [三有映射待核][threePDF] | 南方低海拔常见且北方有夏候鸟；中高频，分类与IUCN来源冲突单列。 [物种][cern:easternCattleEgret] [补证][hkCattle] |
| 72. 环颈雉 | Phasianus colchicus | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内开阔地广布，但局部丰度有差异；中高频且不等同于各地都丰富。 [物种][cern:commonPheasant] |
| 73. 白喉红臀鹎 | Pycnonotus aurigaster | 65 | 1.2131% | 来源LC | [三有][threePDF] | 华南、西南低海拔局部很常见；提高南方常见鸟份额。 [物种][cern:sootyHeadedBulbul] |
| 74. 白颊噪鹛 | Pterorhinus sannio | 45 | 0.8399% | 来源LC | [三有][threePDF] | 中南部、东南及西南适宜灌丛分布；设中频。 [物种][cern:whiteBrowedLaughingthrush] |
| 75. 白鹡鸰 | Motacilla alba | 120 | 2.2396% | 来源LC | [三有][threePDF] | 国内多地常见、适应开阔地与水边；设最高档日常基准。 [物种][cern:whiteWagtail] |
| 76. 紫啸鸫 | Myophonus caeruleus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 国内多地山地适宜生境常见；设中频。 [物种][cern:blueWhistlingThrush] |
| 77. 红嘴山鸦 | Pyrrhocorax pyrrhocorax | 45 | 0.8399% | 来源LC | [三有][threePDF] | 西部高原及北方部分开阔山地分布；给中频区域代表份额。 [物种][cern:redBilledChough] [补证][choughRange] |
| 78. 红嘴蓝鹊 | Urocissa erythroryncha | 65 | 1.2131% | 来源LC | [三有][threePDF] | 中南部及西南林缘、村镇常见；设中高频。 [物种][cern:redBilledBlueMagpie] |
| 79. 红头长尾山雀 | Aegithalos concinnus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 中南部和西南开阔林地常见；设中频。 [物种][cern:blackThroatedBushtit] |
| 80. 绿背山雀 | Parus monticolus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 西南、中部和台湾山地林缘常见；设中频山林代表。 [物种][cern:greenBackedTit] |
| 81. 蓝喉拟啄木鸟 | Psilopogon asiaticus | 30 | 0.5599% | 来源LC | [三有][threePDF] | 西藏东南部和云南适宜热带森林常见；给中低频区域代表份额。 [物种][cern:blueThroatedBarbet] |
| 82. 蓝额红尾鸲 | Phoenicurus frontalis | 30 | 0.5599% | 来源LC | [三有][threePDF] | 中西部高海拔山地较常见，冬季下移；给中低频区域代表份额。 [物种][cern:blueFrontedRedstart] |
| 83. 褐翅鸦鹃 | Centropus sinensis | 45 | 0.8399% | 来源LC | [国家Ⅱ][nationalTable] | 南方低海拔适宜地区常见；中频，二级保护不直接压低权重。 [物种][cern:greaterCoucal] |
| 84. 角百灵 | Eremophila alpestris | 45 | 0.8399% | 来源LC | [三有][threePDF] | 北方、西北和高原适宜开阔地常见；给中频区域代表份额。 [物种][cern:hornedLark] |
| 85. 赤颈鸫 | Turdus ruficollis | 30 | 0.5599% | 来源LC | [三有][threePDF] | 北方及西部繁殖或迁徙、部分越冬地较常见；设季节性中低频。 [物种][cern:redThroatedThrush] |
| 86. 赤麻鸭 | Tadorna ferruginea | 65 | 1.2131% | 来源LC | [三有][threePDF] | 北方、高原繁殖及多地越冬，适宜地区常见；设中高频。 [物种][cern:ruddyShelduck] |
| 87. 赭红尾鸲 | Phoenicurus ochruros | 30 | 0.5599% | 来源LC | [三有][threePDF] | 西北、高原和西部山地多地常见；提高旧预设相对份额，保留区域代表性。 [物种][cern:blackRedstart] |
| 88. 达乌里寒鸦 | Coloeus dauuricus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 国内北方及部分中西部常见；设中频。 [物种][cern:daurianJackdaw] |
| 89. 金翅雀 | Chloris sinica | 65 | 1.2131% | 来源LC | [三有][threePDF] | 国内多地常见留鸟；设中高频。 [物种][cern:greyCappedGreenfinch] |
| 90. 银喉长尾山雀 | Aegithalos glaucogularis | 65 | 1.2131% | 来源LC | [三有][threePDF] | 中国特有，多地林地常见；特有不等于稀有，设中高频。 [物种][cern:silverThroatedBushtit] |
| 91. 长尾缝叶莺 | Orthotomus sutorius | 45 | 0.8399% | 来源LC | [三有][threePDF] | 南方低海拔适宜地区常见；设中频。 [物种][cern:commonTailorbird] |
| 92. 领雀嘴鹎 | Spizixos semitorques | 45 | 0.8399% | 来源LC | [三有][threePDF] | 东南、华南和台湾丘陵常见；设中频。 [物种][cern:collaredFinchbill] |
| 93. 高山兀鹫 | Gyps himalayensis | 10 | 0.1866% | 来源NT | [国家Ⅱ][nationalTable] | 西部高山高原大型猛禽，低地日常遇见机会有限；设低频，NT与二级仅作独立注记。 [物种][cern:himalayanVulture] [补证][cmsVulture] |
| 94. 黄嘴朱顶雀 | Linaria flavirostris | 30 | 0.5599% | 来源LC | [三有][threePDF] | 西北、高原及中西部适宜地区较常见；给中低频区域代表份额。 [物种][cern:twite] |
| 95. 黄嘴蓝鹊 | Urocissa flavirostris | 30 | 0.5599% | 来源LC | [三有][threePDF] | 喜马拉雅和西南山地森林常见；给中低频区域代表份额。 [物种][cern:yellowBilledBlueMagpie] |
| 96. 黄腹花蜜鸟 | Cinnyris ornatus | 30 | 0.5599% | LC*（分类口径） | [三有映射待核][threePDF] | 国内南部热带地区分布，海南较常见；给中低频区域份额，旧广义分类单列。 [物种][cern:ornateSunbird] [补证][hkSunbird] |
| 97. 黄臀鹎 | Pycnonotus xanthorrhous | 45 | 0.8399% | 来源LC | [三有][threePDF] | 西南及部分中东部局部常见；设中频。 [物种][cern:brownBreastedBulbul] |
| 98. 黄颈凤鹛 | Yuhina flavicollis | 18 | 0.3359% | 来源LC | [三有][threePDF] | 西藏东南部和云南部分山地不常见；设低频特色。 [物种][cern:whiskeredYuhina] |
| 99. 黑尾鸥 | Larus crassirostris | 45 | 0.8399% | 来源LC | [三有][threePDF] | 国内沿海常见，有季节迁移；设中频海岸代表。 [物种][cern:blackTailedGull] |
| 100. 黑短脚鹎 | Hypsipetes leucocephalus | 45 | 0.8399% | 来源LC | [三有][threePDF] | 南方和西南山地常绿林常见；设中频。 [物种][cern:blackBulbul] |

## 5. 分类、来源冲突与待核记录

稳定 ID 不因学名修订而改变，也不合并现有两个喜鹊或两个大山雀条目。原目录缺少的学名在本表按对应资料补齐，是拟议元数据，不表示已修改资源；对普通鵟的英文/学名身份需在实施时校正。

| 鸟种 / ID | 核对记录 |
|---|---|
| 珠颈斑鸠 / `spottedDove` | 三有条目同中文名，使用学名Streptopelia chinensis；本表保留名称差异供复核。 官方三有第 66 项，PDF 第 5 页，列名 珠颈斑鸠 / Streptopelia chinensis。[名录][threePDF]  |
| 红尾水鸲 / `plumbeousWaterRedstart` | 三有条目同中文名，使用学名Rhyacornis fuliginosa；本表保留名称差异供复核。 官方三有第 804 项，PDF 第 25 页，列名 红尾水鸲 / Rhyacornis fuliginosa。[名录][threePDF]  |
| 普通鵟 / `commonBuzzard` | 目录英文Common Buzzard容易指向Buteo buteo；中文普通鵟及本次来源为Buteo japonicus。建议补全学名、校正英文，保留稳定ID。  |
| 喜鹊 / `orientalMagpie` | 目录喜鹊为Pica serica；三有371号喜鹊使用Pica pica，与本项目另一个欧亚喜鹊ID相关，拆分后的法定名录映射待核。 官方三有第 371 项，PDF 第 14 页，列名 喜鹊 / Pica pica。[名录][threePDF]  |
| 大嘴乌鸦 / `largeBilledCrow` | 未匹配本次核对的2021重点名录及2023三有名录；不推断为不受其他法律或地方规定保护。  |
| 绿头鸭 / `mallard` | 三有名录备注仅限野外种群。 官方三有第 29 项，PDF 第 4 页，列名 绿头鸭 / Anas platyrhynchos。[名录][threePDF]  |
| 暗绿绣眼鸟 / `swinhoesWhiteEye` | CERN为Zosterops simplex，三有610号暗绿绣眼鸟列Zosterops japonicus；分类拆分与名录映射待核。 官方三有第 610 项，PDF 第 20 页，列名 暗绿绣眼鸟 / Zosterops japonicus。[名录][threePDF]  |
| 大山雀 / `greatTit` | 目录为Parus minor，应与Parus major分开；CERN远东山雀页记NR，HKBWS的LC注明并入广义P. major。三有397号大山雀列Parus cinereus，不能只靠中文同名完成匹配。 官方三有第 397 项，PDF 第 15 页，列名 大山雀 / Parus cinereus。[名录][threePDF] [HKBWS Japanese Tit / Parus minor][hkTit] |
| 普通翠鸟 / `commonKingfisher` | CERN将其标为二级，与本次国家名录核对不一致；采用三有270号普通翠鸟Alcedo atthis，不沿用百科的二级标记。 官方三有第 270 项，PDF 第 11 页，列名 普通翠鸟 / Alcedo atthis。[名录][threePDF]  |
| 小嘴乌鸦 / `carrionCrow` | 未匹配本次核对的2021重点名录及2023三有名录；不推断为不受其他法律或地方规定保护。  |
| 山噪鹛 / `plainLaughingthrush` | 三有条目同中文名，使用学名Garrulax davidi；本表保留名称差异供复核。 官方三有第 668 项，PDF 第 21 页，列名 山噪鹛 / Garrulax davidi。[名录][threePDF]  |
| 欧亚大山雀 / `eurasianGreatTit` | Parus major与本项目greatTit的Parus minor分别保留；三有396号列欧亚大山雀Parus major。 官方三有第 396 项，PDF 第 14 页，列名 欧亚大山雀 / Parus major。[名录][threePDF]  |
| 牛背鹭 / `easternCattleEgret` | 目录和CERN使用Bubulcus coromandus；CERN记NR，HKBWS记LC并引用广义B. ibis资料。三有254号牛背鹭列Bubulcus ibis；保留来源口径差异。 官方三有第 254 项，PDF 第 11 页，列名 牛背鹭 / Bubulcus ibis。[名录][threePDF] [HKBWS Eastern Cattle Egret][hkCattle] |
| 环颈雉 / `commonPheasant` | 三有名录备注仅限野外种群。 官方三有第 13 项，PDF 第 4 页，列名 环颈雉 / Phasianus colchicus。[名录][threePDF]  |
| 白颊噪鹛 / `whiteBrowedLaughingthrush` | 三有条目同中文名，使用学名Garrulax sannio；本表保留名称差异供复核。 官方三有第 671 项，PDF 第 21 页，列名 白颊噪鹛 / Garrulax sannio。[名录][threePDF]  |
| 红嘴山鸦 / `redBilledChough` | CERN页面缺完整分布段落，另以Shanghai Birding中国分布说明补充。 官方三有第 373 项，PDF 第 14 页，列名 红嘴山鸦 / Pyrrhocorax pyrrhocorax。[名录][threePDF]  |
| 蓝额红尾鸲 / `blueFrontedRedstart` | 三有条目同中文名，使用学名Phoenicuropsis frontalis；本表保留名称差异供复核。 官方三有第 798 项，PDF 第 25 页，列名 蓝额红尾鸲 / Phoenicuropsis frontalis。[名录][threePDF]  |
| 达乌里寒鸦 / `daurianJackdaw` | 三有条目同中文名，使用学名Corvus dauuricus；本表保留名称差异供复核。 官方三有第 375 项，PDF 第 14 页，列名 达乌里寒鸦 / Corvus dauuricus。[名录][threePDF]  |
| 高山兀鹫 / `himalayanVulture` | CERN和CMS均记NT；近危不等于IUCN受威胁三类别，且不与中国二级保护相互换算。 [UNEP/CMS Gyps himalayensis][cmsVulture] |
| 黄腹花蜜鸟 / `ornateSunbird` | 目录为Cinnyris ornatus；CERN及三有886号黄腹花蜜鸟使用广义Cinnyris jugularis。HKBWS提供ornatus条目与LC记录，最新独立评估年未核实。 官方三有第 886 项，PDF 第 27 页，列名 黄腹花蜜鸟 / Cinnyris jugularis。[名录][threePDF] [HKBWS Ornate Sunbird][hkSunbird] |

普通翠鸟尤其需要纠正：物种知识平台给出的“二级”不直接采信，本次采用官方三有第 270 项 Alcedo atthis 及重点名录交叉核对结果。百科保护等级不能覆盖法定名录。[物种记录][cern:commonKingfisher] [官方三有][threePDF] [国家重点名录][nationalTable]

## 6. 预期可见度与后续校准

下表是固定概率、独立有效物种抽样下的理论计算，不是跑应用得到的观测，不包含群飞成群数量或驻留时长差异。

| 单种权重 | 单次机会 | 平均首次遇见抽数 1/p | 至少见过一次达 95% 所需抽数 |
|---:|---:|---:|---:|
| 120 | 2.2396% | 44.6 | 133 |
| 65 | 1.2131% | 82.4 | 246 |
| 30 | 0.5599% | 178.6 | 534 |
| 10 | 0.1866% | 535.8 | 1604 |

100/500/1000 次有效抽样的预期不同鸟种数分别约为 59.3/95.7/99.1。即便全部权重为正，也不保证有限时间内集齐全部；不能根据正常调度机会间隔直接换算以上抽数为分钟。

初始发布后先检查“实际选择计数”与对应时刻有效候选权重是否相符，区分调度次数、有效入场次数、在场数量和驻留时长；采样验证可本地完成，无需引入用户数据上传。再根据体验决定是否压缩 12:1 差距或增加独立探索模式。权重改版需记录系统默认版本、逐种变更理由和影响；默认模式跟随当前默认表，手动模式保留用户明确覆盖的值，未覆盖项跟随系统默认。

若以后引入观鸟统计数据，必须明确数据授权、年份、覆盖地区、完整清单、观察努力、分类版本和验证方法。本次定性预设可立即作为设计输入，但不应换个标题就被包装成实测概率。

## 7. 证据清单与交付验证

配套 JSON 的 settingsContract 记录默认隐藏、勾选调整、取消勾选和重置规则；取消勾选后缓存的手动值不参与运行，重置会清除缓存。配套 JSON 收录每种鸟的 stable ID、采用与原始学名、旧目录权重、拟议权重、计算占比、来源原始 IUCN 标签、名录匹配状态/条目号/页码、分类备注和来源链接。所有来源访问日期为本报告日期；CERN 页面能提取到历史 revisionId 时一并记录，官方三有 PDF 记录 SHA-256。研究时只提取事实字段和短摘要，没有把百科全文提交进项目。

研究局限：大部分 IUCN 状态依赖机构知识平台汇编，未逐种核实最新独立评估；5 项法定分类映射待核；未获得全国标准化原始观测数据。上述局限不会被数值权重掩盖。权重可独立使用，元数据不确定项必须保留待核显示。

交付验收针对文档与 JSON：100 个唯一 ID 与目录完全对应、每项系统默认值均为有限正权重、总权重及条件占比一致、每行有来源与分档理由、保护计数和待核项一致、调研阶段未变更应用代码，未运行应用编译或运行测试。后续 macOS 开发与实际验收结果见 [V2 实施记录](../PROBABILITY-SYSTEM-V2-IMPLEMENTATION.md)。

### 主要来源

- [国家重点保护野生动物名录：2021年第3号公告][national2021]：国家重点保护等级依据。
- [上海市绿化和市容管理局：国家重点保护野生动物名录全文表][nationalTable]：逐种核对国家重点名录。
- [调整后的三有名录：2023年第17号公告][three2023]：三有名录版本依据。
- [有重要生态、科学、社会价值的陆生野生动物名录全文，57页][threePDF]：逐种核对三有；URL中的202605不是名录修订日期。
- [国家林草局2026年鸟类保护成果新闻发布会][official2026]：交叉确认2021和2023两份保护名录的版本背景。
- [Cornell eBird: Modeling Relative Abundance][ebirdMethod]：解释标准清单遇见率与区域、季节、观察努力的关系；未取得全国原始数据作拟合。
- [HKBWS Japanese Tit / Parus minor][hkTit]：独立分类；页面LC明确沿用广义P. major口径。
- [HKBWS Eastern Cattle Egret][hkCattle]：补充Bubulcus coromandus资料与LC记录，保留与CERN NR的差异。
- [HKBWS Ornate Sunbird][hkSunbird]：补充Cinnyris ornatus资料；旧广义分类资料不可直接等同新分类评估。
- [UNEP/CMS Gyps himalayensis][cmsVulture]：高山兀鹫NT交叉核对；CMS附录不是中国保护等级。
- [Shanghai Birding: Red-billed Chough][choughRange]：补充CERN缺失的中国分布段落。

逐种来源在上表的“物种”链接中；JSON 是完整索引。

[national2021]: https://www.forestry.gov.cn/c/www/gkzfwj/546057.jhtml
[nationalTable]: https://lhsr.sh.gov.cn/gjzdbhysdwml/
[three2023]: https://www.forestry.gov.cn/c/www/gsgg/509640.jhtml
[threePDF]: https://www.forestry.gov.cn/u/cms/www/202605/19143215z39s.pdf
[official2026]: https://www.forestry.gov.cn/lyj/1/zxzb/20260702/679018.html
[ebirdMethod]: https://ebird.github.io/ebird-one-day-rel-abd-workshop/abundance.html
[hkTit]: https://avifauna.hkbws.org.hk/species/0270/034800
[hkCattle]: https://avifauna.hkbws.org.hk/species/0170/023000
[hkSunbird]: https://avifauna.hkbws.org.hk/species/0420/052300
[cmsVulture]: https://www.cms.int/species/gyps-himalayensis
[choughRange]: https://www.shanghaibirding.com/birds-of-china/red-billed-chough/
[cern:redWhiskeredBulbul]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E8%80%B3%E9%B9%8E
[cern:treeSparrow]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BA%BB%E9%9B%80
[cern:lightVentedBulbul]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%99%BD%E5%A4%B4%E9%B9%8E
[cern:spottedDove]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%8F%A0%E9%A2%88%E6%96%91%E9%B8%A0
[cern:chineseBlackbird]: https://wiki.biodiversity.cern.ac.cn/index.php/%E4%B9%8C%E9%B8%AB
[cern:magpieRobin]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%B9%8A%E9%B8%B2
[cern:longTailedShrike]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%A3%95%E8%83%8C%E4%BC%AF%E5%8A%B3
[cern:nightHeron]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%A4%9C%E9%B9%AD
[cern:plumbeousWaterRedstart]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E5%B0%BE%E6%B0%B4%E9%B8%B2
[cern:littleEgret]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%99%BD%E9%B9%AD
[cern:greyHeron]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%8B%8D%E9%B9%AD
[cern:commonKestrel]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E9%9A%BC
[cern:peregrineFalcon]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%B8%B8%E9%9A%BC
[cern:blackKite]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%91%E9%B8%A2
[cern:commonBuzzard]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%99%AE%E9%80%9A%E9%B5%9F
[cern:orientalMagpie]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%96%9C%E9%B9%8A
[cern:azureWingedMagpie]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%81%B0%E5%96%9C%E9%B9%8A
[cern:largeBilledCrow]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%A4%A7%E5%98%B4%E4%B9%8C%E9%B8%A6
[cern:hoopoe]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%88%B4%E8%83%9C
[cern:barnSwallow]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%AE%B6%E7%87%95
[cern:mallard]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BB%BF%E5%A4%B4%E9%B8%AD
[cern:asianKoel]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%99%AA%E9%B9%83
[cern:swinhoesWhiteEye]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%9A%97%E7%BB%BF%E7%BB%A3%E7%9C%BC%E9%B8%9F
[cern:blackHeadedGull]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E5%98%B4%E9%B8%A5
[cern:whimbrel]: https://wiki.biodiversity.cern.ac.cn/index.php/%E4%B8%AD%E6%9D%93%E9%B9%AC
[cern:piedKingfisher]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%96%91%E9%B1%BC%E7%8B%97
[cern:eurasianWoodcock]: https://wiki.biodiversity.cern.ac.cn/index.php/%E4%B8%98%E9%B9%AC
[cern:blackDrongo]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%91%E5%8D%B7%E5%B0%BE
[cern:chinesePondHeron]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%B1%A0%E9%B9%AD
[cern:yellowRumpedFlycatcher]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%99%BD%E7%9C%89%E5%A7%AC%E9%B9%9F
[cern:yellowBrowedWarbler]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%84%E7%9C%89%E6%9F%B3%E8%8E%BA
[cern:greatTit]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%BF%9C%E4%B8%9C%E5%B1%B1%E9%9B%80
[cern:commonMoorhen]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%91%E6%B0%B4%E9%B8%A1
[cern:greatSpottedWoodpecker]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%A4%A7%E6%96%91%E5%95%84%E6%9C%A8%E9%B8%9F
[cern:vinousThroatedParrotbill]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%A3%95%E5%A4%B4%E9%B8%A6%E9%9B%80
[cern:blackWingedStilt]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%91%E7%BF%85%E9%95%BF%E8%84%9A%E9%B9%AC
[cern:eurasianCoot]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%99%BD%E9%AA%A8%E9%A1%B6
[cern:redBilledLeiothrix]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E5%98%B4%E7%9B%B8%E6%80%9D%E9%B8%9F
[cern:blackCollaredStarling]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%91%E9%A2%86%E6%A4%8B%E9%B8%9F
[cern:commonKingfisher]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%99%AE%E9%80%9A%E7%BF%A0%E9%B8%9F
[cern:littleRingedPlover]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%87%91%E7%9C%B6%E9%B8%BB
[cern:yellowBilledGrosbeak]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%91%E5%B0%BE%E8%9C%A1%E5%98%B4%E9%9B%80
[cern:redFlankedBluetail]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E8%83%81%E8%93%9D%E5%B0%BE%E9%B8%B2
[cern:collaredScopsOwl]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%A2%86%E8%A7%92%E9%B8%AE
[cern:asianBarredOwlet]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%96%91%E5%A4%B4%E9%B8%BA%E9%B9%A0
[cern:littleOwl]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%B5%E7%BA%B9%E8%85%B9%E5%B0%8F%E9%B8%AE
[cern:silkyStarling]: https://wiki.biodiversity.cern.ac.cn/index.php/%E4%B8%9D%E5%85%89%E6%A4%8B%E9%B8%9F
[cern:crestedMyna]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%85%AB%E5%93%A5
[cern:greatCrestedGrebe]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%87%A4%E5%A4%B4%E9%B8%8A%E9%B7%89
[cern:daurianRedstart]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%8C%97%E7%BA%A2%E5%B0%BE%E9%B8%B2
[cern:taiwanBarbet]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%8F%B0%E6%B9%BE%E6%8B%9F%E5%95%84%E6%9C%A8%E9%B8%9F
[cern:groundTit]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%9C%B0%E5%B1%B1%E9%9B%80
[cern:greatEgret]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%A4%A7%E7%99%BD%E9%B9%AD
[cern:uplandBuzzard]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%A4%A7%E9%B5%9F
[cern:littleGrebe]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%B0%8F%E9%B8%8A%E9%B7%89
[cern:carrionCrow]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%B0%8F%E5%98%B4%E4%B9%8C%E9%B8%A6
[cern:plainLaughingthrush]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%B1%B1%E5%99%AA%E9%B9%9B
[cern:orientalTurtleDove]: https://wiki.biodiversity.cern.ac.cn/index.php/%E5%B1%B1%E6%96%91%E9%B8%A0
[cern:easternSpotBilledDuck]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%96%91%E5%98%B4%E9%B8%AD
[cern:eurasianNuthatch]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%99%AE%E9%80%9A%E4%B4%93
[cern:rufousBreastedAccentor]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%A3%95%E8%83%B8%E5%B2%A9%E9%B9%A8
[cern:eurasianMagpie]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%AC%A7%E4%BA%9A%E5%96%9C%E9%B9%8A
[cern:eurasianGreatTit]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%AC%A7%E4%BA%9A%E5%A4%A7%E5%B1%B1%E9%9B%80
[cern:marshTit]: https://wiki.biodiversity.cern.ac.cn/index.php/%E6%B2%BC%E6%B3%BD%E5%B1%B1%E9%9B%80
[cern:ashyDrongo]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%81%B0%E5%8D%B7%E5%B0%BE
[cern:eurasianCollaredDove]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%81%B0%E6%96%91%E9%B8%A0
[cern:greyTreepie]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%81%B0%E6%A0%91%E9%B9%8A
[cern:whiteCheekedStarling]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%81%B0%E6%A4%8B%E9%B8%9F
[cern:henricsLaughingthrush]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%81%B0%E8%85%B9%E5%99%AA%E9%B9%9B
[cern:indianWhiteEye]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%81%B0%E8%85%B9%E7%BB%A3%E7%9C%BC%E9%B8%9F
[cern:easternCattleEgret]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%89%9B%E8%83%8C%E9%B9%AD
[cern:commonPheasant]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%8E%AF%E9%A2%88%E9%9B%89
[cern:sootyHeadedBulbul]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%99%BD%E5%96%89%E7%BA%A2%E8%87%80%E9%B9%8E
[cern:whiteBrowedLaughingthrush]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%99%BD%E9%A2%8A%E5%99%AA%E9%B9%9B
[cern:whiteWagtail]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%99%BD%E9%B9%A1%E9%B8%B0
[cern:blueWhistlingThrush]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%B4%AB%E5%95%B8%E9%B8%AB
[cern:redBilledChough]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E5%98%B4%E5%B1%B1%E9%B8%A6
[cern:redBilledBlueMagpie]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E5%98%B4%E8%93%9D%E9%B9%8A
[cern:blackThroatedBushtit]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BA%A2%E5%A4%B4%E9%95%BF%E5%B0%BE%E5%B1%B1%E9%9B%80
[cern:greenBackedTit]: https://wiki.biodiversity.cern.ac.cn/index.php/%E7%BB%BF%E8%83%8C%E5%B1%B1%E9%9B%80
[cern:blueThroatedBarbet]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%93%9D%E5%96%89%E6%8B%9F%E5%95%84%E6%9C%A8%E9%B8%9F
[cern:blueFrontedRedstart]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%93%9D%E9%A2%9D%E7%BA%A2%E5%B0%BE%E9%B8%B2
[cern:greaterCoucal]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%A4%90%E7%BF%85%E9%B8%A6%E9%B9%83
[cern:hornedLark]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%A7%92%E7%99%BE%E7%81%B5
[cern:redThroatedThrush]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%B5%A4%E9%A2%88%E9%B8%AB
[cern:ruddyShelduck]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%B5%A4%E9%BA%BB%E9%B8%AD
[cern:blackRedstart]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%B5%AD%E7%BA%A2%E5%B0%BE%E9%B8%B2
[cern:daurianJackdaw]: https://wiki.biodiversity.cern.ac.cn/index.php/%E8%BE%BE%E4%B9%8C%E9%87%8C%E5%AF%92%E9%B8%A6
[cern:greyCappedGreenfinch]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%87%91%E7%BF%85%E9%9B%80
[cern:silverThroatedBushtit]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%93%B6%E5%96%89%E9%95%BF%E5%B0%BE%E5%B1%B1%E9%9B%80
[cern:commonTailorbird]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%95%BF%E5%B0%BE%E7%BC%9D%E5%8F%B6%E8%8E%BA
[cern:collaredFinchbill]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%A2%86%E9%9B%80%E5%98%B4%E9%B9%8E
[cern:himalayanVulture]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%AB%98%E5%B1%B1%E5%85%80%E9%B9%AB
[cern:twite]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%84%E5%98%B4%E6%9C%B1%E9%A1%B6%E9%9B%80
[cern:yellowBilledBlueMagpie]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%84%E5%98%B4%E8%93%9D%E9%B9%8A
[cern:ornateSunbird]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%84%E8%85%B9%E8%8A%B1%E8%9C%9C%E9%B8%9F
[cern:brownBreastedBulbul]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%84%E8%87%80%E9%B9%8E
[cern:whiskeredYuhina]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%84%E9%A2%88%E5%87%A4%E9%B9%9B
[cern:blackTailedGull]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%91%E5%B0%BE%E9%B8%A5
[cern:blackBulbul]: https://wiki.biodiversity.cern.ac.cn/index.php/%E9%BB%91%E7%9F%AD%E8%84%9A%E9%B9%8E

[annualRepost]: https://www.sohu.com/a/1067387857_121106875

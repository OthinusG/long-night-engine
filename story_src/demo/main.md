#scene scene_demo_intro

@bg office
@bgm bgm_trial
@char protagonist center normal

辩护律师[normal]:
我是成步堂风格的新人辩护律师。
今天是我接受委托调查案件的第一天。

@sfx sfx_desk_slam
@char protagonist center confident

辩护律师[confident]:
首先，必须准备好我的辩护律师徽章。

@evidence_add attorney_badge
@sfx sfx_evidence_present

辩护律师[normal]:
出发去现场之前，先整理一下案发情报。

@goto scene_investigation_start

#scene scene_investigation_start

@bg office
@bgm bgm_investigation
@char assistant right normal

助手[normal]:
所长，现场调查已经准备就绪了。
您可以随时在事务所和案发现场之间移动。

@investigation location_office
@goto scene_court_intro

#location location_office

@name 律师事务所
@bg office
@character 助手
@move -> location_crime_scene
@present attorney_badge -> scene_present_badge_office
@generic_present -> scene_present_generic_office

## topic case_overview

@title 关于案件委托
@scene scene_topic_overview

## topic suspect_alibi

@title 不在场证明
@scene scene_topic_alibi
@locked

#location location_crime_scene

@name 案发现场
@bg crime_scene
@move -> location_office
@generic_present -> scene_present_generic_office

## hotspot window

@rect 0.10 0.10 0.20 0.30
@scene scene_examine_window

## hotspot table_report

@rect 0.35 0.45 0.30 0.25
@scene scene_examine_table

#scene scene_examine_window

@char protagonist center thinking

辩护律师[thinking]:
窗户紧闭着，从内部上了插销。
外面似乎下过雨，窗沿上留有水痕。

@return


#scene scene_topic_overview

@char assistant right cheerful

助手[cheerful]:
被告人坚称案发当时自己并未进入过现场房间。
只要能找到记录案发时间的报告，就能揭开真相！

@talk_unlock suspect_alibi
@return

#scene scene_topic_alibi

@char assistant right normal

助手[normal]:
根据目击者说法，案发时间是在昨夜九点。
但现场似乎遗留了非常关键的书面证据。

@return

#scene scene_present_badge_office

@char assistant right worried

助手[worried]:
所长，这是您的律师徽章，不用每次都出示给我看啦！

@return

#scene scene_present_generic_office

@char assistant right normal

助手[normal]:
这件证物……或许在法庭上才能派上用场呢。

@return

#scene scene_examine_table

@char protagonist center thinking

辩护律师[thinking]:
桌上放着一份刚刚整理好的现场记录……
这就是关键的《案发报告》！

@evidence_add crime_report
@sfx sfx_evidence_present

辩护律师[confident]:
有了这个，现场调查就全部完成了。
立刻动身前往法庭！

@investigation_end


#scene scene_court_intro

@bg courtroom_judge
@bgm bgm_testimony
@char judge center normal

法官[normal]:
现在开庭审理本次案件。
请检方传唤证人入庭作证。

@char prosecutor center normal

检察官[normal]:
控方证人已经在庭，随时可以陈述证言。

@goto scene_court_testimony

#scene scene_court_testimony

@bg courtroom_witness
@char witness center nervous

证人[nervous]:
我……我这就把昨晚目击到的事情一五一十地说出来！

@testimony testimony_demo_01
@penalty 20
@wrong -> scene_court_wrong

## statement demo_s01

证人[normal]:
昨晚九点整，我正好路过案发现场的门前。

@press -> scene_press_s01

## statement demo_s02

证人[nervous]:
屋里一片漆黑，但我清清楚楚看见了被告人的身影！

@press -> scene_press_s02

## statement demo_s03

证人[normal]:
案发时间确凿无疑就是九点，绝对没有记错！

@press -> scene_press_s03
@present crime_report -> scene_break_testimony

## statement demo_s04

证人[nervous]:
所以，凶手除了被告人之外，不可能有别人了！

@press -> scene_press_s04

@endtestimony
@goto scene_demo_ending

#scene scene_press_s01

@sfx sfx_hold_it
@char protagonist center point

辩护律师[point]:
等等！
你为什么会在那个时间路过那里？

@char witness center nervous

证人[nervous]:
我只是散步路过而已，这并不犯法吧！

@return

#scene scene_press_s02

@sfx sfx_hold_it
@char protagonist center thinking

辩护律师[thinking]:
等等！
既然屋里一片漆黑，你又是怎么看清人的样貌的？

@char witness center sweat

证人[sweat]:
这、这个嘛……走廊上的月光稍微照亮了一点！

@return

#scene scene_press_s03

@sfx sfx_hold_it
@char protagonist center point

辩护律师[point]:
等等！
你对案发时间为何如此笃定？

@char witness center normal

证人[normal]:
因为我当时特意看了一眼表，时间清清楚楚！

@return

#scene scene_press_s04

@sfx sfx_hold_it
@char protagonist center normal

辩护律师[normal]:
等等！
你确认现场附近没有其他可疑人员吗？

@char witness center nervous

证人[nervous]:
没有，我发誓绝对没有看见其他人！

@return

#scene scene_court_wrong

@sfx sfx_damage
@char protagonist center sweat

辩护律师[sweat]:
难道是我看错了证据……？！

@char judge center stern

法官[stern]:
辩护人，请不要提出毫无根据的无理指控！
法庭将予以惩罚！

@return

#scene scene_break_testimony

@sfx sfx_objection
@char protagonist center point

辩护律师[point]:
看招！
证人，你的证言存在着致命的矛盾！

@char witness center shocked

证人[shocked]:
什……什么？！

@char protagonist center confident

辩护律师[confident]:
这份《案发报告》上记录得清清楚楚！
案发现场的供电记录显示，当晚八点半至九点半全楼停电且门窗紧闭！
在完全无光的密封环境中，你根本不可能单凭肉眼看清室内！

@char witness center break
@sfx sfx_damage

证人[break]:
哇啊啊啊啊啊——！！

@char prosecutor center sweat

检察官[sweat]:
这……怎么可能……！

@bg courtroom_judge
@char judge center gavel
@sfx sfx_gavel

法官[gavel]:
肃静！本案事实已经彻底明朗！
辩护人的举证有力，事实清楚无误！

@return

#scene scene_demo_ending

@bg office
@bgm bgm_reminiscence
@char protagonist center confident

辩护律师[confident]:
审判顺利结束，被告人被当庭宣布无罪。
这就是逆转裁判引擎的标准流程示范！

#scene scene_procedure_continue

辩护律师[confident]:
庭审程序必须依法进行，不能草率结案！

@procedure_end
@return

#scene scene_procedure_fail

辩护律师[sweat]:
看来我的抗辩未能获得法庭认可……

@procedure_end
@return

#scene scene_inspect_watch_glass

辩护律师[thinking]:
仔细观察怀表的表盘玻璃，上面有明显的撞击裂痕。

@return

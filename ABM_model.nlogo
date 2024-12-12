extensions [csv]

globals [
  station-coordinates ; 存储站点及其经纬度的映射
  in-data ; 存储每个时间段的站点人数（从你的 entry 数据集中导入）
  current-tick-index ; 当前时间段（从第 2 列开始）
  total-passengers
  die-count

  station-closure ; 用于存储关闭站点的名称
  closure-duration ; 存储关闭的持续时间
  closure-end-tick ; 存储关闭的结束 tick
  closure-start-tick
  green-park-passenger-count
  result-tick
  start-tick
  duration-min
]


breed [stations station]   ;; 定义站点 turtle
breed [passengers passenger] ;; 定义乘客 turtle


stations-own [
  station-id ; 站点 ID
  passenger-count ; 当前站点的乘客人数
]

passengers-own [
  target-station ; 当前目标站点
  ticks-to-next ; 剩余到下一站点的时间
  location
  personal-tick
  previous-link
]

links-own [
  weight ;; 用于记录通过的乘客数量
]


to setup
  clear-all
  reset-ticks

  set station-closure "Green Park"
  set closure-duration 70 ;; 自定义关闭持续的 tick 数
  set closure-end-tick -1 ;; 初始值为 -1，表示没有关闭
  set closure-start-tick 140;;1000
  ;set closure-start-tick 364;;1600
  set green-park-passenger-count 0

  set start-tick closure-start-tick - 1
  set result-tick closure-start-tick + closure-duration - 1
  set duration-min (result-tick - start-tick)/ 7

  set current-tick-index 2
  set die-count 0

  ;; 导入站点经纬度数据
  let coordinates-data csv:from-file "/Users/wendili/Desktop/stations_with_coordinates.csv"
  ;; 跳过第一行（header row）
  set coordinates-data but-first coordinates-data
  ;;print coordinates-data

  ;; 创建站点坐标映射
  set station-coordinates []
  foreach coordinates-data [
    row ->
    let station-stop item 0 row
    let lon item 1 row
    let lat item 2 row

    ;; 如果经纬度非空，将其存储到 station-coordinates 列表
    if (lon != "" and lat != "") [
      set station-coordinates lput (list station-stop (list lon lat)) station-coordinates
    ]
  ]

  ;;读取entry
  set in-data csv:from-file "/Users/wendili/Desktop/entry_sat_2022_clean_2.csv"
  set in-data but-first in-data ;; 跳过标题行
  set current-tick-index 1 ;; 初始时间段为第二列（数据文件中第一列是站点名称）
  print in-data


  ;; 将经纬度转换为 patch 坐标，并生成站点
  generate-stations

  ;; 读取 OD 数据并创建连接
  let od-data csv:from-file "/Users/wendili/Desktop/sat_OD_copy.csv"
  set od-data but-first od-data ;; 跳过 header row
  create-links-from-od od-data

  generate-passengers
  reset-ticks
end

to go

    ;; 检查是否需要启动或结束关闭
  if ticks = closure-start-tick [ ;; 设置特定 tick 触发关闭
    initiate-closure
  ]
  if closure-end-tick = ticks [
    end-closure
  ]

  ;; 更新总乘客数量
  set total-passengers count passengers

  if ticks mod 7 = 0 [
    ask links [ set weight 0 ]
  ]

  ;; 每隔 15 个 ticks 生成新乘客
  if ticks mod 7 = 0 [
    generate-passengers
  ]

  ask passengers [
    ifelse ticks-to-next > 0 [
      set ticks-to-next ticks-to-next - 1
      let new-target-station one-of [link-neighbors] of target-station
      ;; 检查目标站点是否为关闭站点或与关闭站点连接
      ifelse new-target-station != nobody [
        ifelse not is-closed new-target-station [
          set target-station new-target-station
          ;; 更新通过的链接权重
          let current-link one-of links with [
            (end1 = [location] of myself and end2 = [target-station] of myself) or
            (end1 = [target-station] of myself and end2 = [location] of myself)
          ]
          if current-link != nobody [
            ask current-link [ set weight weight + 1
              ;set thickness thickness + 0.001
            ]
          ]
        ] [
          set ticks-to-next ticks-to-next + 10

        ]
      ] [
        set die-count die-count + 1
        die
      ]
    ] [
      set die-count die-count + 1
      die
    ]
    ;; 更新个人 tick
    set personal-tick personal-tick + 1
  ]


  ;; 计算所有链接的权重总和
  let total-weight sum [weight] of links

  ;; 更新图表
  ;; 更新图表
  set-current-plot "Total Link Weight"
  set-current-plot-pen "Weight Sum"
  plotxy ticks total-weight

  ;; 在第 7 个 tick 记录累计的权重总和
  ;;if ticks mod 6 = 0 [
    ;;set-current-plot "Cumulative Link Weight"
    ;;set-current-plot-pen "Cumulative Weight"
    ;;plotxy ticks total-weight
  ;;]


  if ticks = closure-start-tick [ ;; Replace 50 with your desired tick
    export-weights-table (word "/Users/wendili/Desktop/netlogo/start" closure-start-tick ticks ".csv")
  ]

  if ticks = start-tick [ ;; Replace 50 with your desired tick
    export-weights-table (word "/Users/wendili/Desktop/netlogo/start1600.csv")
  ]

  if ticks = result-tick [ ;; Replace 50 with your desired tick
    export-weights-table (word "/Users/wendili/Desktop/netlogo/result1600_" duration-min ".csv")
  ]

  ;; 每 tick 重置链接权重（在所有更新完成后）
  ;;ask links [ set weight 0 ]

  ;; 更新时间
  tick
end

to initiate-closure
  let closed-station one-of stations with [station-id = station-closure]
  if closed-station != nobody [
    ;; 设置站点颜色为绿色表示关闭
    ask closed-station [
      set color green
      set size 2

    ]

    ;; 设置关闭持续时间
    set closure-end-tick ticks + closure-duration

    ;; 更新连接的乘客的 ticks-to-next
    let connected-links links with [
      end1 = closed-station or end2 = closed-station
    ]
    ask connected-links [
      let affected-passengers passengers-on-link
      ask affected-passengers [
        set ticks-to-next ticks-to-next + 5 ;; 增加 ticks-to-next
      ]
    ]
  ]
end

to-report is-closed [station_name]
  ;; 检查指定站点是否处于关闭状态
  report station_name = station-closure and ticks < closure-end-tick
end

to-report passengers-on-link
  ;; 返回连接上的所有乘客
  report passengers with [
    ([location] of self = [end1] of myself or [location] of self = [end2] of myself)
  ]
end

to end-closure
  let closed-station one-of stations with [station-id = station-closure]
  if closed-station != nobody [
    ;; 恢复站点颜色
    ask closed-station [ set color blue ]
  ]
  ;; 重置关闭变量
  set closure-end-tick -1
end

;; 根据 station-coordinates 生成站点
to generate-stations
  foreach station-coordinates [
    entry ->
    let station-name first entry
    let lon item 0 last entry
    let lat item 1 last entry

    ;; 转换经纬度到 patch 坐标
    let px map-lon-to-px lon
    let py map-lat-to-py lat

    let entry-row first filter [row -> item 0 row = station-name] in-data
    let initial-passengers 0 ;; 默认值

    ;; 如果找到匹配的行，从第二列提取初始值
    if (entry-row != []) [
      set initial-passengers item current-tick-index entry-row
    ]

    ;; 创建站点
    create-stations 1 [
      setxy px py
      set shape "circle"
      set color blue
      set size 0.5
      set station-id station-name ;; 使用 station-id 作为标识符
      set passenger-count initial-passengers ;; 初始化乘客人数
    ]
  ]
end

;; 创建链接
to create-links-from-od [od-data]
  foreach od-data [
    row ->
    let source item 0 row
    let target item 1 row

    ;; 使用 station-id 进行匹配
    let source-turtle one-of turtles with [station-id = source]
    let target-turtle one-of turtles with [station-id = target]

    if (source-turtle != nobody and target-turtle != nobody) [
      ask source-turtle [
        create-link-with target-turtle [
          set color gray
          set thickness 0.1
          set weight 0
        ]
      ]
    ]
  ]
end

;; 辅助函数：将经度转换为 NetLogo 的 x 坐标
to-report map-lon-to-px [lon]
  let lon-values map [entry -> item 0 last entry] station-coordinates
  let min-lon min lon-values
  let max-lon max lon-values
  report ((lon - min-lon) / (max-lon - min-lon)) * (max-pxcor - min-pxcor) + min-pxcor
end

;; 辅助函数：将纬度转换为 NetLogo 的 y 坐标（上下镜像翻转）
to-report map-lat-to-py [lat]
  let lat-values map [entry -> item 1 last entry] station-coordinates
  let min-lat min lat-values
  let max-lat max lat-values

  ;; 基础映射公式
  ;;let mapped-y ((lat - min-lat) / (max-lat - min-lat)) * (max-pycor - min-pycor) + min-pycor
  report ((lat - min-lat) / (max-lat - min-lat)) * (max-pycor - min-pycor) + min-pycor
  ;; 上下镜像翻转
  ;;report max-pycor - (mapped-y - min-pycor)
end


to generate-passengers
  ;; 读取 OD 数据
  let od-data csv:from-file "/Users/wendili/Desktop/entry_sat_2022_clean_2.csv"
  set od-data but-first od-data ;; 跳过标题行

  ;; 检查当前列是否超出范围或为空
  let column-count length first od-data ;; 获取总列数
  if current-tick-index >= column-count [
    print "All columns processed, no more passengers to generate."
    stop
  ]

  ;; 遍历每行 OD 数据，根据当前列生成乘客
  foreach od-data [
    row ->
    let station-name item 0 row       ;; 第一列是站点名称
    let passenger-num precision item current-tick-index row 0 ;; 当前列的乘客数量，取整为整数

    ;; 简单过滤：如果是关闭的站点且在关闭时间范围内，直接跳过
    if station-name = station-closure and ticks >= closure-start-tick and ticks < closure-end-tick [
      ;; 关闭站点跳过逻辑
      print (word "Skipping passenger generation for closed station: " station-name)
      stop
    ]
    if station-name = "Green Park" [
      set green-park-passenger-count green-park-passenger-count + passenger-num
      print (word "Green Park Passenger Count: " green-park-passenger-count)
    ]

    ;; 继续生成其他站点的乘客
    let starting-station one-of stations with [station-id = station-name]
    if starting-station != nobody [
      ;; 一次性创建 passenger-num 数量的乘客
      create-passengers passenger-num [
        set color red
        set shape "person"
        set location starting-station
        set size 1
        move-to starting-station

        setxy (xcor + random-float 0.5 - 0.25)
              (ycor + random-float 0.5 - 0.25)

        ;; 随机选择目标站点
        let targeted-station one-of [link-neighbors] of starting-station
        set target-station targeted-station
        set ticks-to-next random 30 + 2

        set personal-tick ticks
      ]
    ]
  ]

  ;; 更新到下一列
  set current-tick-index current-tick-index + 1
end



to export-weights-table [file-name]
  ;; Create an empty list to store the table rows
  let rows []

  ;; Add a header row
  set rows lput (list "Source Station" "Target Station" "Weight") rows

  ;; Loop through all links and record their weight
  ask links [
    let source [station-id] of end1
    let target [station-id] of end2
    let link-weight weight
    set rows lput (list source target link-weight) rows
  ]

  ;; Write the table to a CSV file
  file-open file-name
  foreach rows [
    row -> file-print csv:to-row row
  ]
  file-close

  print (word "Exported weights table to " file-name)
end

@#$#@#$#@
GRAPHICS-WINDOW
210
10
1791
812
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-60
60
-30
30
0
0
1
ticks
30.0

BUTTON
8
13
73
46
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
97
13
160
46
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
0
71
200
221
total-passenger
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-passengers"

PLOT
0
238
200
388
Total Link Weight
Ticks
Total Weight
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Weight Sum" 1.0 0 -16777216 true "" "plot Weight Sum"

PLOT
0
406
200
556
green-park-passenger
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot green-park-passenger-count"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@

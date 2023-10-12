local tdlua=require"tdlua"

local bot = require"tg.tdlua-tdbot"
-- ^^ Враппер над tdlua позволяющий писать ботов используя API tdbot (костыльная штука), но упрощает написание
local api = require"tg.tdbot-wrapper"
-- ^^ Враппер над API tdbot'а. Уже умерший проект, но, опять же, т.к. у меня были наработки по нему, сделанные ещё до смерти - пока использую это.

-- TODO: когда-нибудь переписать на tdlua (возможно, сделав свой враппер) без этих костылей


local i = require"inspect"
local json = require'cjson'
local b64 = require"lib.base64"

client=tdlua()
_G.tdbot_function = bot.getCallback()
-- ^^ функция должна быть глобальной и должна называться именно так (захардкожена в враппере, т.к. он писался под оригинальный `tdbot`)

-- tdlua.setLogLevel(2)

function table.shuf(x)
  for i = #x, 2, -1 do
    local j = math.random(i)
    x[i], x[j] = x[j], x[i]
  end
end

function table.create(t) -- luacheck: no globals
  return setmetatable(t or {}, {__index = table})
end

local T = table.create -- luacheck: no globals


math.randomseed(os.time())

local function get_answer_buttons(t) -- {{{ получить кнопки для ответа из таблицы
  local ret = T{}
  local buttons = T{}

  for _,v in ipairs(t.good) do
    buttons:insert(v) -- добавляем в таблицу с будущими кнопками "правильные" ответы
  end
  for _,v in ipairs(t.bad) do
    buttons:insert(v) -- добавляем в таблицу с будущими кнопками "направильные" ответы
  end
  buttons:shuf() -- "Перемешиваем" таблицу (чтобы кнопки имели разное положение каждый раз)

  local function is_good(answer) -- {{{ проверяем, является ли ответ "правильным"
    for _,v in ipairs(t.good) do
      if v == answer then return true end
    end
    return false
  end -- }}}

  for _,v in ipairs(buttons) do -- перебираем таблицу с заготовками кнопок
    local cb_k = math.random(100,1000) -- случайное число для формирования пары значений
                                       -- для последующей возможности отличить нажатие кнопки
                                       -- с "правильным" ответом от кнопки с "неправильным"
    local cb_v
    if is_good(v) then -- если ответ относится к "правильным"
      cb_v = (cb_k*2)^2 -- делаем второе число "предсказуемым" и связанным с первым предсказуемой формулой
    else -- иначе
      cb_v = math.random(10000,1000000)*2 -- присваиваем случайное число. Но чтобы было не так очевидно делаем его тоже чётным
    end

    ret:insert({
      text = v,
      type = {
        ["@type"]="inlineKeyboardButtonTypeCallback",
        data = b64.encode( -- кодируем в base64
          json.encode({ -- превращаем таблицу со значениями в json-строку
            id = math.random(1,1000000), -- случайное число, ID кнопки
            [b64.encode(tostring(cb_k))] = b64.encode(tostring(cb_v)), -- пара чисел, чтобы отличать "правильные" ответы
          })
        ),
      },
    })
  end
  return ret
end -- }}}

local function not_empty(a) -- {{{
  return a and #a>0
end -- }}}

local function get_name(user_info) -- {{{
  if not user_info then user_info = {} end
  local fn = user_info.firstname
  local ln = user_info.lastname
  local un = user_info.username
  local name = T{fn or "Человек без имени"}

  if ln and not_empty(ln) then
    name[#name+1] = ln
  elseif un and not_empty(un) then
    name[#name+1] = ("(@%s)"):format(un)
  end
  return name:concat(" ")
end -- }}}

local function get_user_info(id) -- {{{
    local info
    api.getUser(id,function(...)
      local arg = {...}
      local u = arg[2]
      info = {
        firstname = u.first_name,
        lastname = u.last_name,
        username = u.username,
      }
    end)
    return info
end -- }}}

local function cb(data)
	-- print(i(data));
  if data["@type"] == "updateNewCallbackQuery" then -- button pressed
    local payload = data.payload
    -- if payload["@type"] == "callbacQueryPayloadData" then
      local chat_id = data.chat_id
      local msg_id = data.message_id
      local user_id = data.sender_user_id
      local data = payload.data
      --[[{{{
      local decoded_data_str
      if data then
        local ok
        ok, decoded_data_str = pcall(b64.decode,data)
        if not ok then return end -- не раскодировалось, значит не работаем с этим
      end
      -- print(i(json.decode(b64.decode(data))))
      local decoded_data_t
      if decoded_data_str then
        local ok, res = pcall(json.decode, decoded_data_str)
        if ok then
          decoded_data_t = T(res)
        else
          return
        end
      end

      if decoded_data_t then
        for k,v in pairs(decoded_data_t) do
          if k ~= "u" then
          else -- if not id and not user info
            local ok_k, kd = pcall(b64.decode, k)
            local ok_v, vd = pcall(b64.decode, v)

            if ok_k and ok_v then
              if tonumber(vd) == (kd*2)^2 then
                api.sendText(chat_id,msg_id,"Правильно","html") -- TODO: вернуть права на написание
              else
                api.sendText(chat_id,msg_id, "Неправильно","html") -- TODO:кикнуть
              end
            else
              return
            end
          end
        end
      end
    --}}}]]
    -- end
  elseif (data["@type"] == "updateNewMessage") then
    local msg = data.message
    if msg.chat_id ~= -1001162087440 then print(msg.chat_id) return end
    if msg.content then
      if msg.content["@type"] == "messageChatAddMembers" then -- Вход в чат
		    local user_id=msg.content.member_user_ids[1]
		    local join_msg_id=msg.id
      elseif msg.content["@type"] == "messageText" and not msg.is_outgoing then -- (Входящее) сообщение в чате
        local user_id = msg.sender.user_id
        local name = get_name(get_user_info(user_id))

      --[[{{{
        local answers = T{ -- ответы
          { "Прочитали ли вы правила?", { good = { "Да" }, bad = { "Я бот", "Я спамер" }, }, },
          { "Вы вступаете в чат обмена в городе", { good = { "Томск (и Северск)" }, bad = { "Москва", "Тверь", "Владивосток" }, }, },
        }
      }}}]]

        if msg.content.text.text == "/j" then -- {{{ -- если сообщение - это "/j" (для отладки, чтобы не перевходить постоянно)
          local nl = string.char(10) -- символ переноса строки

          --[[{{{
          local q = answers[math.fmod(math.random(100),#answers)+1] -- выбираем случайный вопрос
          local question = q[1] -- сам вопрос
          local btns = get_answer_buttons(q[2], { user_id = user_id, msg_id = msg.id } ) -- кнопки
          local reply_markup = { -- создаём "клавиатуру" с кнопками ответов
            ["@type"]="replyMarkupInlineKeyboard",
            rows = { btns }
          }
          --}}}]]
--[=[{{{
          local msgtext=(
            [[Здравствуйте, <a href="tg://user/?id=%d">%s</a>! В последнее время, нам очень сильно надоели спам-боты, ]]
          ..[[поэтому мы ввели защиту от спама.]]..nl
          ..[[<b>Сейчас вы не можете ничего писать в чат.</b>]]..nl
          ..[[Чтобы получить возможность писать - прочитайте <a href="tg://resolve?domain=reuse_tomsk&post=20161">правила</a> и подтвердите что вы не бот и не спамер.]]
          ..nl..nl..[[Пожалуйста, в течение минуты ответьте на вопрос:]]..nl..[[%s]]
          ):format(
            user_id,
            name,
            question
          )
  }}}]=]

          local msgtext = (
            [[Здравствуйте, <a href="tg://user/?id=%d">%s</a>!]]
            ..nl
            ..[[Пожалуйста, прочитайте наши <a href="tg://resolve?domain=reuse_tomsk&post=20161">правила</a>]]
          ):format(user_id,name)
          api.sendText(
            msg.chat_id,
            msg.id,
            msgtext,
            'html'
            --[[{{{
            ,
            disable_web_page_preview,
            clear_draft,
            disable_notification,
            from_background,
            reply_markup
          }}}]]
          )
        elseif true then
          local m = msg.content.text.text:lower()
          if not m:match"#ищу" and not m:match"#отдам" then
            local nl = string.char(10) -- символ переноса строки
            local msgtext = (
              [[К сожалению, <a href="tg://user/?id=%d">%s</a>, мне пришлось удалить Ваше сообщение.]]
              ..nl..nl
              ..[[Кажется, Вы не читали наши <a href="tg://resolve?domain=reuse_tomsk&post=20161">правила</a>.]]
              ..nl..nl
              ..[[Если Вы хотите просто пообщаться, можете это сделать в нашей болталке]]
            ):format(user_id, name)
            api.sendText(msg.chat_id, msg.id, msgtext, 'html')
            api.deleteMessages(msg.chat_id,{msg.id},1,function(...) print(i({...})) end)
          end -- if not ищу/отдам
        end -- if text = /j else }}}
      end
    end
  end
end

bot.run(cb)

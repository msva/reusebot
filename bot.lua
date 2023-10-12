local tdlua=require"tdlua"

local bot = require"tg.tdlua-tdbot"
-- ^^ Враппер над tdlua позволяющий писать ботов используя API tdbot (костыльная штука), но упрощает написание
local api = require"tg.tdbot-wrapper"
-- ^^ Враппер над API tdbot'а. Уже умерший проект, но, опять же, т.к. у меня были наработки по нему, сделанные ещё до смерти - пока использую это.

-- TODO: когда-нибудь переписать на tdlua (возможно, сделав свой враппер) без этих костылей


local i = require"inspect"
local json = require'cjson'
local b64 = require"lib.base64"
local u8 = require"lua-utf8"

_G.client=tdlua()
_G.tdbot_function = bot.getCallback()
-- ^^ функция должна быть глобальной и должна называться именно так (захардкожена в враппере, т.к. он писался под оригинальный `tdbot`)

--tdlua.setLogLevel(4)

function _G.table.shuf(x)
  for c = #x, 2, -1 do
    local j = math.random(c)
    x[c], x[j] = x[j], x[c]
  end
end

function _G.table.create(t) -- luacheck: no global
  return setmetatable(t or {}, {__index = table})
end

local T = table.create -- luacheck: no global


math.randomseed(os.time())

local function get_answer_buttons(t) -- {{{ получить кнопки для ответа из таблицы
  local ret = T{}
  local buttons = T{}

  for _,v in pairs(t.good) do
    buttons:insert(v) -- добавляем в таблицу с будущими кнопками "правильные" ответы
  end
  for _,v in pairs(t.bad) do
    buttons:insert(v) -- добавляем в таблицу с будущими кнопками "направильные" ответы
  end
  buttons:shuf() -- "Перемешиваем" таблицу (чтобы кнопки имели разное положение каждый раз)

  local function is_good(answer) -- {{{ проверяем, является ли ответ "правильным"
    for _,v in pairs(t.good) do
      if v == answer then return true end
    end
    return false
  end -- }}}

  for _,v in pairs(buttons) do -- перебираем таблицу с заготовками кнопок
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

local function get_chat_admins(id) -- {{{
    local admins = T{}
    api.getChatAdministrators(id,function(...)
      local arg = {...}
      local a = arg[2].administrators or {}
      for _,v in pairs(a) do
        if v["@type"] == "chatAdministrator" then
          admins[v.user_id] = true
        end
      end
    end)
    return admins
end -- }}}

local nl = string.char(10) -- символ переноса строки

local chat_admins = T{}
local jobs = T{}

local cm_exceptions = T{
 ["-1001258220173"] = true
}

local function jobs_do() -- {{{
  for k,v in pairs(jobs) do
    if v.interval then
      if not v.last_run or v.last_run <= os.time()-v.interval then
        v.last_run = os.time()
        v.job(v.args)
      end
    elseif v.at then
      if v.at <= os.time() then
        v.job(v.args)
        jobs[k] = nil
      end
    else
      v.job(v.args)
      jobs[k] = nil
    end
    if v.count then
      if v.count >= 1 then
        v.count = v.count - 1
      else
        jobs[k] = nil
      end
    end
  end
end -- }}}

local forbidden_msgtypes = T{
  messageText = true,
  messageSticker = true,
  messageVideo = true,
  messageAnimatedEmoji = true,
  messageAudio = true,
  messageAnimation = true,
  messageCall = true,
  messageContact = true,
  messageDocument = true,
  messageGame = true,
  messageInvoice = true,
  messageLocation = true,
  -- messagePhoto = true,
  messageVideoNote = true,
  messageVoiceNote = true,
}
--[[
local sent_types = T{
  updateMessageSendSucceeded = true,
  updateMessageSendFailed = true,
  updateDeleteMessages = true
}
 ]]


local rules_link = "tg://resolve?domain=reuse_tomsk&post=45446"


local function cb(data)
  jobs_do()
  -- if sent_types[data["@type"]] then
    print(i(data))
  if (data["@type"] == "updateMessageSendSucceeded") then -- успешно отправленное исходящее сообщение
    local msg = data.message
    local function del_my_msg(msg)
      api.deleteMessages(msg.chat_id,{msg.id},function()end)
    end
    jobs:insert{ job = del_my_msg, args = { chat_id = msg.chat_id, id = msg.id }, at = os.time()+35 }
  elseif (data["@type"] == "updateNewMessage") then
    local msg = data.message
    -- if msg.chat_id ~= -1001162087440 and not msg.chat_id ~= -1001504113465 then print(msg.chat_id) return end -- не реагировать в других чатах кроме отладочного
    if not chat_admins[msg.chat_id] then
      local function fetch_admins(cid)
        local a = get_chat_admins(cid)
        chat_admins[cid] = T(a)
      end
      fetch_admins(msg.chat_id)
      jobs:insert{ interval = 10, job = fetch_admins, args = msg.chat_id }
    -- else
    end
    if msg.content then
      if
      msg.content["@type"] == "messageChatAddMembers"
        or
      msg.content["@type"] == "messageChatJoinByLink"
      then -- Вход в чат
		    local user_id
        if msg.content["@type"] == "messageChatAddMembers" then
          user_id=msg.content.member_user_ids[1]
        else -- messageChatJoinByLink
          user_id=msg.sender_id.user_id
        end
        local name = get_name(get_user_info(user_id))

        local msgtext = (
          [[Здравствуйте, <a href="tg://user/?id=%d">%s</a>!]]
          ..nl
          ..[[Пожалуйста, прочитайте наши <a href="%s">правила</a>]]
        ):format(user_id,name,rules_link)

        api.sendText(
          msg.chat_id,
          msg.id,
          msgtext,
          'html'
        )
        local function del_entry_msg(m)
          api.deleteMessages(m.chat_id,{m.id},function()end)
        end
        jobs:insert{ job = del_entry_msg, args = { chat_id = msg.chat_id, id = msg.id }, at = os.time()+35 }
      elseif forbidden_msgtypes[msg.content["@type"]] then -- сообщения в чате
        if msg.is_outgoing then -- исходящее
            -- print("Исходящее",msg.id)
            -- api.getMessage(msg.chat_id,msg.id,function(...) arg = {...} print(i(arg[2].sender_id.user_id)) end)
        else
          local user_id = msg.sender_id.user_id
          local chan_id = msg.sender_id.chat_id
          if not user_id then
            print("DBG: chan_id: ",chan_id,", msg: ",msg.content.text.text)

            if cm_exceptions[tostring(chan_id)] then
              return -- не удалять
            else
              api.deleteMessages(msg.chat_id,{msg.id},1)
              return
            end
          end
          if chat_admins[msg.chat_id] and chat_admins[msg.chat_id][user_id or chan_id] then
            return -- не удалять
          else
            local name = get_name(get_user_info(user_id))
            local txt = msg.content.text and msg.content.text.text and msg.content.text.text or ""
            local m = u8.lower(txt)
            if #m < 8 or (not m:match"#ищу" and not m:match"#отдам") then
              local msgtext = (
                [[<a href="tg://user/?id=%d">%s</a>, Ваше сообщение было удалено, т.к. не соответствует <a href="%s">правилам</a>.]]
                ..nl
                ..[[Для общения можно пройти в <a href="https://t.me/blablareuse">болталку</a>]]
              ):format(user_id, name, rules_link)
              api.sendText(msg.chat_id, msg.id, msgtext, 'html')
              api.deleteMessages(msg.chat_id,{msg.id},1)
            end -- if not ищу/отдам
          end -- if true (todo: if admin)
        end -- if outgoing/not}}}
      elseif msg.content["@type"] == "messagePhoto" then
        -- TODO: при переписывании по-нормальному (в т.ч. без tdbot-враппера) избавиться от дублирования.
        -- сейчас сделано "просто чтобы работало", и нет времени на оптимизацию. Но смотреть больно.
        local user_id = msg.sender_id.user_id
        local name = get_name(get_user_info(user_id))
        local text = msg.content.caption.text
        local m = u8.lower(text)
        if chat_admins[msg.chat_id] and chat_admins[msg.chat_id][user_id or chan_id] then
          return -- не удалять
        else
          if not msg.media_album_id then
            if #m < 8 or (not m:match"#ищу" and not m:match"#отдам") then
              local msgtext = (
                [[<a href="tg://user/?id=%d">%s</a>, Ваше сообщение было удалено, т.к. не соответствует <a href="%s">правилам</a>.]]
                ..nl
                ..[[Для общения можно пройти в <a href="https://t.me/blablareuse">болталку</a>]]
              ):format(user_id, name, rules_link)
              api.sendText(msg.chat_id, msg.id, msgtext, 'html')
              api.deleteMessages(msg.chat_id,{msg.id},1)
            end
          else
            if #m > 0 then -- пропускать "альбомные" фото с пустым текстом
              -- Суть этого финта ушами в том, что такими являются все, кроме первой (текст прописывается только у первой в альбоме).
              -- Но обратной стороной является то, что если и у первой тоже не будет текста - бот это пропустит.
              -- Чтобы отслеживать более полноценно - алгоритм придётся переусложнить и вводить базу данных
              -- (или использовать для этого врЕменную переменную, которую потом чистить спустя время)
              -- В любом случае, учитывая, что я планирую переписать это нормально - сейчас нет ни времени, ни желания делать более оптимально.
              -- При этом, вряд ли кто-то будет это намеренно эксплуатировать чтобы флудить.
              -- А разовые случаи можно и вручную поудалять.
              -- Так что, затраты на доведение до идеала в текущих условиях себя не окупят
              if #m < 7 or (not m:match"#ищу" and not m:match"#отдам") then
                local msgtext = (
                  [[<a href="tg://user/?id=%d">%s</a>, Ваше сообщение было удалено, т.к. не соответствует <a href="%s">правилам</a>.]]
                  ..nl
                  ..[[Для общения можно пройти в <a href="https://t.me/blablareuse">болталку</a>]]
                ):format(user_id, name, rules_link)
                api.sendText(msg.chat_id, msg.id, msgtext, 'html')
                api.deleteMessages(msg.chat_id,{msg.id},1)
              end
            end
          end
        end
      else
        print("[DEBUG]: Не обработанный тип сообщения",msg.content["@type"])
      end -- if msg.content[@type]
    end -- if msg.content
  end -- if updateNewMessage
end -- cb()

bot.run(cb)

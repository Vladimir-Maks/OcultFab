local TEXT = [[
Добро пожаловать в OcultFab!

Вам предстоит добывать ресурсы и защищаться от врагов, параллельно выстраивая рабочую линию.

ДОБЫЧА
Нажмите левой кнопкой мыши (ЛКМ) на блок, который хотя бы с одной стороны ни к чему не прилегает: он рассыплется на ресурсы. Затем выделите прихвостня (ЛКМ) и прикажите собрать их: правой кнопкой (ПКМ) по ресурсам или кнопкой "Сбор" в меню действий прихвостня.

ПОСТРОЙКИ
Алтарь - призывает юнитов (прихвостней и мимиков)
Помпа - подает ресурсы со склада в тигель
Тигель - плавит твердые ресурсы в жидкость
Цистерна - хранит жидкость
Экстрактор - перерабатывает ресурсы

ЗАЩИТА
Защитным сооружениям для работы нужно жидкое топливо: они сами берут его из цистерны, стоящей в их радиусе.

ВРАГИ
Ночью, если вы прокопались достаточно далеко, начнется обратный отсчет до волны, во время которой на вас нападут враги. С них выпадает ценная добыча.

С каждым днем врагов будет становиться все больше, так что подготовьтесь как следует!]]

-- The engine wraps text by letters, cutting words; so the text is wrapped
-- by words here (at most CHARS_PER_LINE letters per line, fits the 580 px
-- label) and the label gets exactly that many lines in height
-- (autoresize doesn't work inside a scrolling panel).
local CHARS_PER_LINE = 52
local LINE_HEIGHT = 24

-- wraps one paragraph by words: list of lines
local function wrap(paragraph)
    local lines, line = {}, ""
    for word in paragraph:gmatch("%S+") do
        if line == "" then
            line = word
        elseif utf8.length(line) + 1 + utf8.length(word) <= CHARS_PER_LINE then
            line = line .. " " .. word
        else
            table.insert(lines, line)
            line = word
        end
    end
    table.insert(lines, line)
    return lines
end

function on_open()
    local lines = {}
    for paragraph in (TEXT .. "\n"):gmatch("(.-)\n") do
        for _, line in ipairs(wrap(paragraph)) do
            table.insert(lines, line)
        end
    end
    document.text.text = table.concat(lines, "\n")
    document.text.size = {580, (#lines + 1) * LINE_HEIGHT}
end

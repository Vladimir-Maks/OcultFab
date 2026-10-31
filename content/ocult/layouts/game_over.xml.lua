local combat = require "ocult:combat"

function confirm()
    document.root:clear()
    document.root:add("<label pos='0,60' size='320,20' text-align='center' "
        .. "color='#a08890FF'>Удаление мира...</label>")
    combat.confirm_game_over()
end

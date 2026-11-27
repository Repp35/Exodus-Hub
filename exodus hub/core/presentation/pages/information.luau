-- [[ information page ]]
--!optimize 2
-- @modules pageinformation
local UIPage = {}
UIPage.definition = {
  id = "information",
  title = "Informações",
  columns = 1,

  utility = true,
  sections = {
    { title = "Sessão", components = { { kind = "readout", info = "session" } } },
    { title = "Jogo", components = { { kind = "readout", info = "game" } } },
    { title = "Servidor", components = { { kind = "readout", info = "server" } } },
    { title = "Versões", components = { { kind = "readout", info = "versions" } } },
    { title = "Desenvolvedores", components = { { kind = "readout", info = "developers" } } },
  },
}
function UIPage.setup() return true end
UIPage.__contract = { page = 30, provides = { "setup" }, data = { "definition" }, requires = {} }
return UIPage

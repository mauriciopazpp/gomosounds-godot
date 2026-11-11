@tool
extends RefCounted

## Plugin texts in Portuguese and English. The language follows the Godot editor's
## (pt_* = Portuguese, everything else = English); outside the editor, GOMO_LANG (or SFX_LANG) or the system locale.
## New text in the panel? It goes HERE, in both languages: never a literal in the middle of the UI.

const STRINGS := {
	"no_folder": ["sem pasta", "no folder"],
	"from_folder": ["pasta %s", "folder %s"],
	"from_folder_tip": ["Som da pasta %s: vale pra todas as cenas dela.", "Folder %s sound: applies to every scene in it."],
	# account
	"not_connected": ["Não conectado a %s.", "Not connected to %s."],
	"checking": ["Verificando…", "Checking…"],
	"error": ["Erro: %s", "Error: %s"],
	"account_line": ["%s · %s créditos · plano %s", "%s · %s credits · %s plan"],
	"connect": ["Conectar", "Connect"],
	"disconnect": ["Desconectar", "Disconnect"],
	"approve_code": ["Confira se o navegador mostra este código e aprove:", "Check that your browser shows this code and approve it:"],
	"cancel": ["Cancelar", "Cancel"],
	"login_denied": ["Conexão recusada no site.", "Connection denied on the website."],
	"login_expired": ["O código expirou. Tente de novo.", "The code expired. Try again."],
	"login_cancelled": ["Cancelado.", "Cancelled."],
	"welcome_body": ["Gere efeitos sonoros com IA para as cenas deste projeto e instale direto aqui.", "Generate sound effects with AI for this project's scenes and install them right here."],
	"connect_hint": ["Abre o navegador para você aprovar um código. Nenhum som do projeto sai daqui.", "Opens your browser so you can approve a code. No project sound ever leaves here."],
	"account_short": ["%s · %s créditos", "%s · %s credits"],
	"account_menu": ["Conta", "Account"],
	# game
	"game": ["Jogo", "Game"],
	"reload_all": ["Recarregar conta, jogo e cenas", "Reload account, game and scenes"],
	"no_game_linked": ["Nenhum jogo escolhido para este projeto: escolha no painel Gomo Sounds do editor (ou defina GOMO_GAME_ID).", "No game picked for this project: pick one in the Gomo Sounds dock in the editor (or set GOMO_GAME_ID)."],
	"pick_game": ["Escolha um jogo", "Pick a game"],
	"create_game": ["Criar o jogo \"%s\"", "Create the game \"%s\""],
	"create_another_game": ["Criar outro jogo \"%s\"", "Create another game \"%s\""],
	"game_created": ["Jogo \"%s\" criado. Abra no site e conte sobre o jogo: a gente sugere os sons que ele precisa.", "Game \"%s\" created. Open it on the website and tell us about the game: we suggest the sounds it needs."],
	"pick_game_first": ["Escolha o jogo deste projeto primeiro.", "Pick this project's game first."],
	"pick_game_hint": ["Escolha o jogo do Gomo Sounds deste projeto. Ainda não tem? Crie com o botão abaixo.", "Pick this project's Gomo Sounds game. Don't have one yet? Create it with the button below."],
	"open_site": ["Abrir este jogo no site", "Open this game on the website"],
	# 1. upload scenes
	"step_send": ["Enviar cenas", "Send scenes"],
	"send_hint": [
		"Marque as cenas que fazem barulho e envie. Elas chegam na Entrada do site, onde você escolhe a pasta de cada uma.",
		"Tick the scenes that make noise and send them. They land in the website Inbox, where you pick each one's folder.",
	],
	"folders": ["Pastas", "Folders"],
	"privacy_title": ["O que é enviado?", "What gets sent?"],
	"privacy_sent_title": ["Vai para o Gomo Sounds, só ao clicar em Sincronizar:", "Goes to Gomo Sounds, only when you click Sync:"],
	"privacy_sent": [
		"• Nome e descrição da cena (se ela tiver)\n• Uma imagem pequena (256 px) da cena\n• O caminho da cena (ex.: res://units/besouro.tscn), pra ligar a cena ao site\n• O nome do projeto, ao criar o jogo",
		"• Scene name and description (if it has one)\n• A small image (256 px) of the scene\n• The scene path (e.g. res://units/beetle.tscn), to link the scene to the website\n• The project name, when the game is created",
	],
	"privacy_kept_title": ["Nunca sai do projeto:", "Never leaves the project:"],
	"privacy_kept": [
		"• Sons e músicas\n• Scripts e código\n• Modelos 3D, texturas e outros arquivos\n• Cenas que você não marcou",
		"• Sounds and music\n• Scripts and code\n• 3D models, textures and other files\n• Scenes you didn't tick",
	],
	"no_scenes": ["Nenhuma cena encontrada nessas pastas. Ajuste as pastas acima (separe por vírgula) e clique em Procurar cenas.", "No scenes found in these folders. Adjust the folders above (comma separated) and click Find scenes."],
	"rescan": ["Procurar cenas", "Find scenes"],
	"rescan_tip": ["Procura de novo as cenas nas pastas e o que já está no site.", "Looks again for scenes in the folders and for what is already on the website."],
	"rescanning": ["Procurando cenas…", "Looking for scenes…"],
	"inbox_waiting": ["%d na Entrada do site: arraste cada uma para Efeitos sonoros, Ambiente ou Interface.", "%d in the website Inbox: drag each one to Sound effects, Ambience or Interface."],
	"open_inbox": ["Abrir", "Open"],
	"folders_tip": ["Pastas com cenas de unidades/construções, separadas por vírgula. Enter salva.", "Folders with unit/building scenes, comma separated. Enter saves."],
	"filter_scenes": ["Filtrar cenas", "Filter scenes"],
	"sync_selected": ["Sincronizar selecionadas", "Sync selected"],
	"sync_all": ["Sincronizar todas", "Sync all"],
	"sync_tip": [
		"Cena nova: vai pra Entrada do site (nome, descrição e imagem). Lá você escolhe em qual pasta ela entra.\nCena que já está no site: só a IMAGEM é atualizada. Nada é duplicado.\nNenhum som do projeto é enviado.",
		"New scene: goes to the website Inbox (name, description and image). There you pick which folder it goes to.\nScene already on the website: only the IMAGE is refreshed. Nothing is duplicated.\nNo project sound is ever sent.",
	],
	"scenes_count": ["%d cenas · %d no site", "%d scenes · %d on the website"],
	"in_inbox": ["na Entrada", "in the Inbox"],
	"skip_with_sound": ["Não enviar cenas que já têm som", "Don't send scenes that already have sound"],
	"skip_with_sound_tip": [
		"Pula a cena (ou a cena que ela herda ou usa) que já tem um player de áudio ou aponta pra um arquivo de som.\nDesmarque pra ver e enviar todas.",
		"Skips a scene (or a scene it inherits or uses) that already has an audio player or points to a sound file.\nUntick to see and send all of them.",
	],
	"hidden_with_sound": ["%d com som escondidas", "%d with sound hidden"],
	"legend": ["✓ n/m = sons no jogo / sons da cena. Clique numa cena com ✓ para criar os sons dela.", "✓ n/m = sounds in the game / sounds of the scene. Click a scene with ✓ to make its sounds."],
	"select_first": ["Selecione cenas (e um jogo) primeiro.", "Select scenes (and a game) first."],
	"sync_error": ["Erro ao sincronizar: %s", "Sync error: %s"],
	"sync_done": ["Pronto: %d novas na Entrada do site, %d atualizadas (só a imagem).", "Done: %d new in the website Inbox, %d updated (image only)."],
	"inbox_full_skipped": ["Entrada cheia (%d itens): %d cenas ficaram de fora. Ponha os itens nas pastas do site e envie de novo.", "Inbox full (%d items): %d scenes were left out. Put the items into folders on the website and send again."],
	"reading": ["Lendo %s (%d/%d)…", "Reading %s (%d/%d)…"],
	# 2. create sounds
	"step_sounds": ["Criar sons", "Make sounds"],
	"sounds_hint": ["Clique numa cena com ✓ na lista para gerar e escolher os sons dela aqui. Ou faça isso no site.", "Click a scene with ✓ in the list to generate and pick its sounds here. Or do it on the website."],
	"event": ["Som", "Sound"],
	"sound_description": ["Descrição do som", "Sound description"],
	"duration": ["Duração", "Duration"],
	"variations": ["Versões", "Versions"],
	"generate": ["Gerar", "Generate"],
	"update_available": ["Versão nova do plugin: %s (você tem a %s).", "New plugin version: %s (you have %s)."],
	"update_download": ["Baixar", "Download"],
	"generating": ["Gerando %d versões…", "Generating %d versions…"],
	"generated": ["%d versões novas. Saldo: %d créditos.", "%d new versions. Balance: %d credits."],
	"chosen_mark": ["  ✓ escolhida", "  ✓ chosen"],
	"shared_from": ["Compartilhado de %s", "Shared from %s"],
	"use": ["Usar", "Use"],
	"understood": ["IA entendeu: %s", "AI understood: %s"],
	"sent_en": ["Enviado ao gerador (inglês): %s", "Sent to the generator: %s"],
	"unset": ["Tirar", "Remove"],
	"list_tip": [
		"Cada som tem uma LISTA de versões: o jogo sorteia uma a cada toque (sem repetir a anterior).",
		"Each sound has a LIST of versions: the game picks one at random each time (never the same twice in a row).",
	],
	# 3. install
	"step_install": ["Instalar no projeto", "Install into project"],
	"install_button": ["Instalar sons escolhidos", "Install chosen sounds"],
	"install_checking": ["Conferindo o que mudou…", "Checking what changed…"],
	"downloading": ["Baixando…", "Downloading…"],
	"importing": ["Importando no Godot…", "Importing into Godot…"],
	"install_nothing": ["Tudo em dia: nenhum som novo ou alterado.", "All up to date: no new or changed sounds."],
	"layout_label": ["Onde colocar os sons", "Where to put the sounds"],
	"layout_gomo": ["Pasta do Gomo (recomendado)", "Gomo folder (recommended)"],
	"layout_scene_folder": ["Pasta sounds ao lado da cena", "A sounds folder next to the scene"],
	"layout_beside_scene": ["Ao lado da cena", "Next to the scene"],
	"layout_custom": ["Local personalizado", "Custom location"],
	"layout_gomo_hint": ["Tudo em %s, uma pasta por cena. Não encosta no resto do projeto, e desinstalar é apagar uma pasta.", "Everything in %s, one folder per scene. Nothing else in the project is touched, and uninstalling is deleting one folder."],
	"layout_scene_folder_hint": ["Ex.: res://units/aranha/sounds/aranha_ataque.wav. Sons sem cena (Interface, Ambiente) ficam em %s.", "E.g. res://units/spider/sounds/spider_attack.wav. Sounds without a scene (Interface, Ambience) stay in %s."],
	"layout_beside_scene_hint": ["Ex.: res://units/aranha/aranha_ataque.wav. Sons sem cena (Interface, Ambiente) ficam em %s.", "E.g. res://units/spider/spider_attack.wav. Sounds without a scene (Interface, Ambience) stay in %s."],
	"layout_custom_hint": ["Tudo em %s, uma pasta por cena. O caminho fica salvo no projeto.", "Everything in %s, one folder per scene. The path is saved in the project."],
	"custom_placeholder": ["res://audio/sons", "res://audio/sounds"],
	"folder_change": ["Escolher pasta…", "Choose folder…"],
	"folder_show": ["Mostrar no FileSystem", "Show in FileSystem"],
	"folder_invalid": ["Escolha uma pasta dentro do projeto (fora de addons e .godot).", "Pick a folder inside the project (not addons or .godot)."],
	"remove_missing": ["Apagar do projeto os sons que saíram do site", "Delete sounds that were removed on the website"],
	"remove_missing_hint": ["Só os que o plugin baixou e ninguém mexeu. Arquivo seu nunca é apagado nem substituído.", "Only files the plugin downloaded and nobody changed. Your own files are never deleted or replaced."],
	"confirm_title": ["Instalar sons", "Install sounds"],
	"confirm_ok": ["Instalar", "Install"],
	"sum_new": ["%d novos", "%d new"],
	"sum_update": ["%d atualizados", "%d updated"],
	"sum_restore": ["%d restaurados", "%d restored"],
	"sum_move": ["%d mudados de lugar", "%d moved"],
	"sum_remove": ["%d apagados", "%d deleted"],
	"sum_keep": ["%d sem mudança", "%d unchanged"],
	"note_edited": ["Você editou %s: fica a sua versão.", "You edited %s: your version stays."],
	"note_renamed": ["Já existe um arquivo seu em %s: o som vai como %s.", "There is already a file of yours at %s: the sound goes to %s."],
	"note_left_edited": ["Saiu do site, mas você editou: %s fica no projeto (e deixa de ser do plugin).", "Removed on the website, but you edited it: %s stays in the project (and is no longer managed by the plugin)."],
	"note_left": ["Saiu do site e fica no projeto (apagar está desligado): %s", "Removed on the website, kept in the project (deleting is off): %s"],
	"note_move_failed": ["Não deu pra mudar %s de lugar (aberto em outro programa?): ficou onde estava.", "Couldn't move %s (open in another program?): it stayed where it was."],
	"note_overwrote_edit": ["Trocado pela versão do site: %s", "Replaced with the website version: %s"],
	"note_edited_outdated": ["Você editou %s e o site tem versão nova: fica a sua, a não ser que marque abaixo.", "You edited %s and the website has a new version: yours stays unless you tick the box below."],
	"replace_edits": ["Trocar os %d que eu editei pela versão nova do site", "Replace the %d I edited with the new website version"],
	"note_more": ["…e mais %d.", "…and %d more."],
	"installed_where": ["Catálogo em %s.", "Catalog at %s."],
	"cli_importing": ["Importando os arquivos novos no Godot...", "Importing the new files into Godot..."],
	"cli_import_failed": ["A importação falhou. Abra o projeto no editor pra ele importar os sons.", "The import failed. Open the project in the editor so it imports the sounds."],
	"download_failed": ["Falha ao baixar %s: %s", "Failed to download %s: %s"],
	"no_write": ["Sem permissão pra gravar %s.", "No permission to write %s."],
	# network
	"foreign_url": ["URL de outro servidor recusada.", "Refused URL from another server."],
	"request_failed": ["Falha ao iniciar a requisição (%s).", "Failed to start the request (%s)."],
	"offline": ["Sem conexão com o Gomo Sounds. Verifique a internet e tente de novo.", "Can't reach Gomo Sounds. Check your connection and try again."],
}

static var _index := -1


## 0 = Portuguese, 1 = English.
static func index() -> int:
	if _index >= 0:
		return _index
	var lang := OS.get_environment("GOMO_LANG")
	if lang == "":
		lang = OS.get_environment("SFX_LANG")
	if lang == "" and Engine.is_editor_hint():
		# The language the editor IS in (the setting may be empty = "the system's").
		lang = TranslationServer.get_tool_locale()
	if lang == "":
		lang = OS.get_locale()
	_index = 0 if lang.to_lower().begins_with("pt") else 1
	return _index


## Code for the server (Accept-Language): "pt-BR" or "en".
static func http_language() -> String:
	return "pt-BR" if index() == 0 else "en"


static func t(key: String, args: Variant = null) -> String:
	var pair: Array = STRINGS.get(key, [key, key])
	var text: String = pair[index()]
	if args == null:
		return text
	return text % args

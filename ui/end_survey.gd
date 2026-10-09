extends PanelContainer
## Survei singkat di layar akhir (scenes/ui/end_survey.tscn):
## 2 pertanyaan skala 1-5 + kolom masukan & saran (opsional), lalu tombol Kirim.
## Jawaban dikirim ke BalanceLog dan masuk ke file sesi + ringkasan_<penguji>.csv.
## Kalau tester langsung menekan R / Esc tanpa Kirim, isian yang sudah ada tetap disimpan (flush()).

signal answered(tegang: int, adil: int, saran: String)

@onready var feedback: TextEdit = $VBox/Saran/Text
@onready var send_btn: Button = $VBox/Send

var _tegang := 0
var _adil := 0
var _sent := false

func _ready() -> void:
	for i in 5:
		var bt: Button = $VBox/Tegang/Buttons.get_child(i)
		bt.pressed.connect(_pick.bind(true, i + 1))
		var ba: Button = $VBox/Adil/Buttons.get_child(i)
		ba.pressed.connect(_pick.bind(false, i + 1))
	send_btn.pressed.connect(submit)
	send_btn.disabled = true
	$VBox/Thanks.hide()

func _pick(tense: bool, v: int) -> void:
	if tense:
		_tegang = v
	else:
		_adil = v
	send_btn.disabled = not (_tegang > 0 and _adil > 0)

func has_answer() -> bool:
	return _tegang > 0 or _adil > 0 or feedback.text.strip_edges() != ""

func submit() -> void:
	if _sent:
		return
	_sent = true
	feedback.release_focus()
	for n in [$VBox/Title, $VBox/Tegang, $VBox/Adil, $VBox/Saran, send_btn]:
		n.hide()
	$VBox/Thanks.show()
	answered.emit(_tegang, _adil, feedback.text.strip_edges())

## Simpan isian yang belum dikirim (dipanggil sebelum main ulang / kembali ke menu).
func flush() -> void:
	if visible and not _sent and has_answer():
		submit()

## True kalau tester sedang mengetik saran (supaya R / Esc tidak memotong).
func is_typing() -> bool:
	return visible and not _sent and feedback.has_focus()

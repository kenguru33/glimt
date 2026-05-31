[[ -o interactive ]] || return

() {
  local r=$'\e[0m'
  local b=$'\e[1m'
  local P=$'\e[38;2;245;194;231m'   # pink    #f5c2e7
  local M=$'\e[38;2;203;166;247m'   # mauve   #cba6f7
  local B=$'\e[38;2;137;180;250m'   # blue    #89b4fa
  local T=$'\e[38;2;148;226;213m'   # teal    #94e2d5
  local X=$'\e[38;2;205;214;244m'   # text    #cdd6f4
  local S=$'\e[38;2;166;173;200m'   # subtext #a6adc8

  local sep="${M}──${r}"

  local os kern sh cpu mem up pk who cpu_raw bt el

  os="${X}$(sw_vers -productName) $(sw_vers -productVersion)${r}"
  kern="${X}$(uname -r)${r}"
  sh="${X}zsh ${ZSH_VERSION}${r}"
  cpu_raw=$(sysctl -n machdep.cpu.brand_string 2>/dev/null) || cpu_raw=$(sysctl -n hw.model 2>/dev/null)
  cpu="${X}${cpu_raw}${r}"
  mem="${X}$(($(sysctl -n hw.memsize) / 1073741824)) GB${r}"
  bt=$(sysctl -n kern.boottime | awk '{print $4}' | tr -d ',')
  el=$(( $(date +%s) - bt ))
  up="${X}$((el / 3600))h $(( (el % 3600) / 60 ))m${r}"
  pk="${X}$(brew list --formula 2>/dev/null | wc -l | tr -d ' ') (brew)${r}"
  who="${b}${M}${USER}${r}${S}@${r}${B}$(hostname -s)${r}"

  echo ""
  echo "  ${P}/\\_____/\\${r}    ${S}user     ${r}${sep} ${who}"
  echo " ${P}/  ${M}◉${P}   ${M}◉${P}  \\${r}   ${S}os       ${r}${sep} ${os}"
  echo "${P}( ==  ${T}^${P}  == )${r}  ${S}kernel   ${r}${sep} ${kern}"
  echo " ${P})  ${M}glimt${P}  (${r}   ${S}shell    ${r}${sep} ${sh}"
  echo "${P}(  ~~~~~~~  )${r}  ${S}cpu      ${r}${sep} ${cpu}"
  echo " ${P}\\_________/${r}   ${S}memory   ${r}${sep} ${mem}"
  echo "               ${S}uptime   ${r}${sep} ${up}"
  echo "               ${S}packages ${r}${sep} ${pk}"
  echo ""
}

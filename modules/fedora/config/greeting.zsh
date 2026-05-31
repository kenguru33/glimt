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

  local os kern sh cpu mem up pk who up_secs

  os="${X}$(source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo 'Fedora Linux')${r}"
  kern="${X}$(uname -r)${r}"
  sh="${X}zsh ${ZSH_VERSION}${r}"
  cpu="${X}$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //;s/  */ /g')${r}"
  mem="${X}$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%d/%d MB", (t-a)/1024, t/1024}' /proc/meminfo)${r}"
  up_secs=$(awk '{printf "%d", $1}' /proc/uptime)
  up="${X}$((up_secs / 3600))h $(( (up_secs % 3600) / 60 ))m${r}"
  pk="${X}$(rpm -qa 2>/dev/null | wc -l) (rpm)${r}"
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

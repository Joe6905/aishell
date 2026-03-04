#!/usr/bin/env bash
# ============================================================
#  AI Shell — Bash script with Claude AI integration
#  Usage: chmod +x ai_shell.sh && ./ai_shell.sh
#  Requires: curl, jq  (install: sudo apt install curl jq)
# ============================================================

# ── Config ──────────────────────────────────────────────────
CLAUDE_MODEL="claude-sonnet-4-20250514"
HISTORY_FILE="$HOME/.ai_shell_history"
CONFIG_FILE="$HOME/.ai_shell_config"
MAX_TOKENS=1024

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Load or prompt for API key ───────────────────────────────
load_api_key() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi

    if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        echo -e "${YELLOW}No API key found.${RESET}"
        echo -ne "${CYAN}Enter your Anthropic API key: ${RESET}"
        read -r -s key
        echo
        ANTHROPIC_API_KEY="$key"
        echo "ANTHROPIC_API_KEY=\"$key\"" > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        echo -e "${GREEN}✓ API key saved to $CONFIG_FILE${RESET}"
    fi
}

# ── Check dependencies ───────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in curl jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${RESET}"
        echo -e "${DIM}Install with: sudo apt install ${missing[*]}  (or brew install ...)${RESET}"
        exit 1
    fi
}

# ── Banner ───────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║          AI SHELL  —  powered by Claude   ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${DIM}Model : ${CLAUDE_MODEL}${RESET}"
    echo -e "  ${DIM}Type  : ${YELLOW}help${RESET}${DIM} to see available commands${RESET}"
    echo -e "  ${DIM}Type  : ${YELLOW}exit${RESET}${DIM} or press Ctrl+C to quit${RESET}"
    echo
}

# ── Help menu ────────────────────────────────────────────────
print_help() {
    echo -e "\n${BOLD}${CYAN}┌─ AI Shell Commands ────────────────────────────┐${RESET}"
    echo -e "${YELLOW}  ask      <question>${RESET}     Ask AI anything"
    echo -e "${YELLOW}  explain  <topic>${RESET}        Get an explanation"
    echo -e "${YELLOW}  generate <task>${RESET}         Generate code / scripts"
    echo -e "${YELLOW}  summarize <topic>${RESET}       Get a concise summary"
    echo -e "${YELLOW}  debug    <error>${RESET}        Debug code or errors"
    echo -e "${YELLOW}  translate <text>${RESET}        Translate text"
    echo -e "${YELLOW}  compare  <A> vs <B>${RESET}     Compare two things"
    echo -e "${YELLOW}  shell    <task>${RESET}         Get a shell one-liner"
    echo -e "${YELLOW}  chat${RESET}                   Start multi-turn chat mode"
    echo -e "${CYAN}─────── Built-in ──────────────────────────────────${RESET}"
    echo -e "${YELLOW}  history${RESET}                Show command history"
    echo -e "${YELLOW}  clear${RESET}                  Clear the screen"
    echo -e "${YELLOW}  apikey${RESET}                 Update your API key"
    echo -e "${YELLOW}  help${RESET}                   Show this help"
    echo -e "${YELLOW}  exit / quit${RESET}            Exit AI Shell"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${RESET}\n"
}

# ── Spinner ──────────────────────────────────────────────────
spinner_pid=""
start_spinner() {
    local msg="${1:-Thinking}"
    (
        local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        local i=0
        while true; do
            printf "\r  ${CYAN}${frames[$i]}${RESET}  ${DIM}${msg}...${RESET}"
            ((i = (i + 1) % ${#frames[@]}))
            sleep 0.08
        done
    ) &
    spinner_pid=$!
}

stop_spinner() {
    if [[ -n "$spinner_pid" ]]; then
        kill "$spinner_pid" 2>/dev/null
        wait "$spinner_pid" 2>/dev/null
        spinner_pid=""
        printf "\r\033[K"   # clear spinner line
    fi
}

# ── Call Claude API ──────────────────────────────────────────
call_ai() {
    local system_prompt="$1"
    local user_msg="$2"

    local payload
    payload=$(jq -n \
        --arg model "$CLAUDE_MODEL" \
        --argjson max_tokens "$MAX_TOKENS" \
        --arg system "$system_prompt" \
        --arg user "$user_msg" \
        '{
            model: $model,
            max_tokens: $max_tokens,
            system: $system,
            messages: [{ role: "user", content: $user }]
        }')

    local response
    response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${ANTHROPIC_API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -d "$payload")

    # Check for API error
    local err
    err=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$err" ]]; then
        echo -e "${RED}API Error: ${err}${RESET}" >&2
        return 1
    fi

    echo "$response" | jq -r '.content[0].text // "No response received."'
}

# ── Multi-turn chat ──────────────────────────────────────────
chat_mode() {
    echo -e "\n${BOLD}${MAGENTA}Chat Mode${RESET} — type ${YELLOW}exit${RESET} to return to shell\n"
    local messages="[]"
    local system_prompt="You are a helpful AI assistant in a terminal chat session. Be concise and clear."

    while true; do
        echo -ne "${MAGENTA}you${RESET}${DIM} ❯${RESET} "
        read -r user_input

        [[ "$user_input" == "exit" || "$user_input" == "quit" ]] && break
        [[ -z "$user_input" ]] && continue

        # Append user message to history
        messages=$(echo "$messages" | jq \
            --arg content "$user_input" \
            '. + [{ role: "user", content: $content }]')

        start_spinner "Claude is typing"

        local payload
        payload=$(jq -n \
            --arg model "$CLAUDE_MODEL" \
            --argjson max_tokens "$MAX_TOKENS" \
            --arg system "$system_prompt" \
            --argjson messages "$messages" \
            '{
                model: $model,
                max_tokens: $max_tokens,
                system: $system,
                messages: $messages
            }')

        local response
        response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: ${ANTHROPIC_API_KEY}" \
            -H "anthropic-version: 2023-06-01" \
            -d "$payload")

        stop_spinner

        local err
        err=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
        if [[ -n "$err" ]]; then
            echo -e "${RED}Error: $err${RESET}"
            continue
        fi

        local reply
        reply=$(echo "$response" | jq -r '.content[0].text // "No response."')

        # Append assistant message
        messages=$(echo "$messages" | jq \
            --arg content "$reply" \
            '. + [{ role: "assistant", content: $content }]')

        echo -e "\n${CYAN}${BOLD}Claude${RESET}${DIM} ❯${RESET}"
        echo -e "${reply}" | sed 's/^/  /'
        echo
    done

    echo -e "${DIM}Exiting chat mode.${RESET}\n"
}

# ── Pretty-print AI response ─────────────────────────────────
print_response() {
    local text="$1"
    echo -e "\n${GREEN}┌─ AI Response ─────────────────────────────────────${RESET}"
    echo -e "$text" | sed 's/^/│  /'
    echo -e "${GREEN}└────────────────────────────────────────────────────${RESET}\n"
}

# ── Save to history ──────────────────────────────────────────
save_history() {
    echo "[$(date '+%Y-%m-%d %H:%M')] $*" >> "$HISTORY_FILE"
}

# ── Main REPL ────────────────────────────────────────────────
main() {
    check_deps
    load_api_key
    print_banner

    local SYSTEM_BASE="You are an AI assistant embedded in a Unix shell. 
Be concise, accurate, and developer-friendly. 
Use plain text — avoid markdown headers. 
Use backticks for code/commands inline."

    while true; do
        # Prompt
        echo -ne "${GREEN}${BOLD}user${RESET}${DIM}@${RESET}${CYAN}aishell${RESET}${DIM}:${RESET}${YELLOW}~${RESET}${GREEN} ❯ ${RESET}"
        read -r -e input
        [[ -z "$input" ]] && continue

        # Add to readline history
        history -s "$input"
        save_history "$input"

        local verb rest
        verb=$(echo "$input" | awk '{print tolower($1)}')
        rest=$(echo "$input" | cut -d' ' -f2-)

        case "$verb" in

            exit|quit)
                echo -e "\n${DIM}Goodbye.${RESET}\n"
                exit 0
                ;;

            clear)
                clear
                print_banner
                ;;

            help)
                print_help
                ;;

            history)
                if [[ -f "$HISTORY_FILE" ]]; then
                    echo -e "\n${DIM}$(tail -20 "$HISTORY_FILE")${RESET}\n"
                else
                    echo -e "${DIM}No history yet.${RESET}"
                fi
                ;;

            apikey)
                echo -ne "${CYAN}New API key: ${RESET}"
                read -r -s newkey; echo
                ANTHROPIC_API_KEY="$newkey"
                echo "ANTHROPIC_API_KEY=\"$newkey\"" > "$CONFIG_FILE"
                chmod 600 "$CONFIG_FILE"
                echo -e "${GREEN}✓ Key updated.${RESET}"
                ;;

            chat)
                chat_mode
                ;;

            ask)
                [[ -z "$rest" ]] && echo -e "${RED}Usage: ask <question>${RESET}" && continue
                start_spinner "Thinking"
                result=$(call_ai "$SYSTEM_BASE" "$rest")
                stop_spinner
                print_response "$result"
                ;;

            explain)
                [[ -z "$rest" ]] && echo -e "${RED}Usage: explain <topic>${RESET}" && continue
                start_spinner "Explaining"
                result=$(call_ai "$SYSTEM_BASE" "Explain \"$rest\" clearly for a developer. Keep it concise.")
                stop_spinner
                print_response "$result"
                ;;

            generate)
                [[ -z "$rest" ]] && echo -e "${RED}Usage: generate <task>${RESET}" && continue
                start_spinner "Generating"
                result=$(call_ai "$SYSTEM_BASE" "Generate code or a script for: $rest. Include a brief explanation.")
                stop_spinner
                print_response "$result"
                ;;

            summarize)
                [[ -z "$rest" ]] && echo -e "${RED}Usage: summarize <topic>${RESET}" && continue
                start_spinner "Summarizing"
                result=$(call_ai "$SYSTEM_BASE" "Give a short, clear summary of: $rest")
                stop_spinner
                print_response "$result"
                ;;

            debug)
                [[ -z "$rest" ]] && echo -e "${RED}Usage: debug <error or code>${RESET}" && continue
                start_spinner "Debugging"
                result=$(call_ai "$SYSTEM_BASE" "Debug this and suggest a fix:\n\n$rest")
                stop_spinner
                print_response "$result"
                ;;

            translate)
                [[ -z "$rest" ]] && echo -e "${RED}Usage: translate <text>${RESET}" && continue
                start_spinner "Translating"
                result=$(call_ai "$SYSTEM_BASE" "Detect the language and translate this text to English (or if English, to Spanish):\n\n$rest")
                stop_spinner
                print_response "$result"
                ;;

            compare)
                [[ -z "$rest" ]] && echo -e "${RED}Usage: compare <A> vs <B>${RESET}" && continue
                start_spinner "Comparing"
                result=$(call_ai "$SYSTEM_BASE" "Compare $rest. Give key differences in a concise list.")
                stop_spinner
                print_response "$result"
                ;;

            shell)
                [[ -z "$rest" ]] && echo -e "${RED}Usage: shell <task>${RESET}" && continue
                start_spinner "Crafting command"
                result=$(call_ai "$SYSTEM_BASE" "Give me a bash one-liner or short shell script to: $rest. Show the command first, then a brief explanation.")
                stop_spinner
                print_response "$result"
                ;;

            *)
                # Unknown command → send to AI as a general question
                start_spinner "Thinking"
                result=$(call_ai "$SYSTEM_BASE" "$input")
                stop_spinner
                print_response "$result"
                ;;
        esac
    done
}

# ── Trap Ctrl+C cleanly ──────────────────────────────────────
trap 'stop_spinner; echo -e "\n${DIM}Goodbye.${RESET}\n"; exit 0' INT TERM

main

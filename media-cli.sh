#!/bin/sh

anime_query() {
    shift $((OPTIND - 1))
    query="$@"

    version_number="4.2.7"

    # UI

    external_menu() {
        rofi "$1" -sort -dmenu -i -width 1500 -p "$2"
    }

    launcher() {
        [ "$use_external_menu" = "0" ] && [ -z "$1" ] && set -- "+m" "$2"
        [ "$use_external_menu" = "0" ] && fzf "$1" --reverse --prompt "$2"
        [ "$use_external_menu" = "1" ] && external_menu "$1" "$2"
    }

    nth() {
        stdin=$(cat -)
        [ -z "$stdin" ] && return 1
        line_count="$(printf "%s\n" "$stdin" | wc -l | tr -d "[:space:]")"
        [ "$line_count" -eq 1 ] && printf "%s" "$stdin" | cut -f2,3 && return 0
        prompt="$1"
        multi_flag=""
        [ $# -ne 1 ] && shift && multi_flag="$1"
        line=$(printf "%s" "$stdin" | cut -f1,3 | tr '\t' ' ' | launcher "$multi_flag" "$prompt" | cut -d " " -f 1)
        [ -n "$line" ] && printf "%s" "$stdin" | grep -E '^'"${line}"'($|\s)' | cut -f2,3 || exit 1
    }

    die() {
        printf "\33[2K\r\033[1;31m%s\033[0m\n" "$*" >&2
        exit 1
    }

    version_info() {
        printf "%s\n" "$version_number"
        exit 0
    }


    # checks if dependencies are present
    dep_ch() {
        for dep; do
            command -v "$dep" >/dev/null || die "Program \"$dep\" not found. Please install it."
        done
    }

    # SCRAPING

    # extract the video links from reponse of embed urls, extract mp4 links form m3u8 lists
    get_links() {
        episode_link="$(curl -e "https://${allanime_base}" -s --cipher "AES256-SHA256" "https://allanimenews.com/apivtwo/clock.json?id=$*" -A "$agent" | sed 's|},{|\n|g' | sed -nE 's|.*link":"([^"]*)".*"resolutionStr":"([^"]*)".*|\2 >\1|p;s|.*hls","url":"([^"]*)".*"hardsub_lang":"en-US".*|\1|p')"
        case "$episode_link" in
        *crunchyroll*)
            curl -e "https://${allanime_base}" -s --cipher "AES256-SHA256" "$episode_link" -A "$agent" | sed 's|^#.*x||g; s|,.*|p|g; /^#/d; $!N; s|\n| >|' | sort -nr
            ;;
        *repackager.wixmp.com*)
            extract_link=$(printf "%s" "$episode_link" | cut -d'>' -f2 | sed 's|repackager.wixmp.com/||g;s|\.urlset.*||g')
            for j in $(printf "%s" "$episode_link" | sed -nE 's|.*/,([^/]*),/mp4.*|\1|p' | sed 's|,|\n|g'); do
                printf "%s >%s\n" "$j" "$extract_link" | sed "s|,[^/]*|${j}|g"
            done | sort -nr
            ;;
        *//cache.* | *gofcdn.com*)
            if printf "%s" "$episode_link" | head -1 | grep -q "original.m3u"; then
                printf "%s" "$episode_link"
            else
                extract_link=$(printf "%s" "$episode_link" | head -1 | cut -d'>' -f2)
                relative_link=$(printf "%s" "$extract_link" | sed 's|[^/]*$||')
                curl -e "https://${allanime_base}/" -s --cipher "AES256-SHA256" "$extract_link" -A "$agent" | sed 's|^#.*x||g; s|,.*|p|g; /^#/d; $!N; s|\n| >|' | sed "s|>|>${relative_link}|g" | sort -nr
            fi
            ;;
        *) [ -n "$episode_link" ] && printf "%s\n" "$episode_link" ;;
        esac
        printf "Fetching %s Links\n" "$provider_name" 1>&2
    }

    # innitialises provider_name and provider_id. First argument is the provider name, 2nd is the regex that matches that provider's link
    provider_init() {
        provider_name=$1
        provider_id=$(printf "%s" "$resp" | sed -n "$2" | head -1 | cut -d':' -f2)
    }

    # generates links based on given provider
    generate_link() {
        case $1 in
        1) provider_init 'wixmp' '/Default :/p' ;;     # wixmp(default)(m3u8)(multi) -> (mp4)(multi)
        2) provider_init 'pstatic' '/Default B :/p' ;; # pstatic(default backup)(mp4)(multi)
        3) provider_init 'vrv' '/Ac :/p' ;;            # vrv(crunchyroll)(m3u8)(multi)
        4) provider_init 'sharepoint' '/S-mp4 :/p' ;;  # sharepoint(mp4)(single)
        5) provider_init 'usercloud' '/Uv-mp4 :/p' ;;  # usercloud(mp4)(single)
        *) provider_init 'gogoanime' '/Luf-mp4 :/p' ;; # gogoanime(m3u8)(multi)
        esac
        [ -n "$provider_id" ] && get_links "$provider_id"
    }

    select_quality() {
        case "$1" in
        best) result=$(printf "%s" "$links" | head -n1) ;;
        worst) result=$(printf "%s" "$links" | grep -E '^[0-9]{3,4}' | tail -n1) ;;
        *) result=$(printf "%s" "$links" | grep -m 1 "$1") ;;
        esac
        [ -z "$result" ] && printf "Specified quality not found, defaulting to best\n" 1>&2 && result=$(printf "%s" "$links" | head -n1)
        printf "%s" "$result" | cut -d'>' -f2
    }

    # gets embed urls, collects direct links into provider files, selects one with desired quality into $episode
    get_episode_url() {
        # get the embed urls of the selected episode
        episode_embed_gql="query (\$showId: String!, \$translationType: VaildTranslationTypeEnumType!, \$episodeString: String!) {    episode(        showId: \$showId        translationType: \$translationType        episodeString: \$episodeString    ) {        episodeString sourceUrls    }}"

        resp=$(curl -e "https://${allanime_base}" -s --cipher "AES256-SHA256" -G "https://api.${allanime_base}/allanimeapi" --data-urlencode "variables={\"showId\":\"$id\",\"translationType\":\"$mode\",\"episodeString\":\"$ep_no\"}" --data-urlencode "query=$episode_embed_gql" -A "$agent" | tr '{}' '\n' | sed 's|\\u002F|\/|g;s|\\||g' | sed -nE 's|.*sourceUrl":".*clock\?id=([^"]*)".*sourceName":"([^"]*)".*|\2 :\1|p')
        # generate links into sequential files
        provider=1
        i=0
        while [ "$i" -lt 6 ]; do
            generate_link "$provider" >"$cache_dir"/"$i" &
            provider=$((provider % 6 + 1))
            : $((i += 1))
        done
        wait
        # select the link with matching quality
        links=$(cat "$cache_dir"/* | sed 's|^Mp4-||g' | sort -g -r -s)
        episode=$(select_quality "$quality")
        [ -z "$episode" ] && die "Episode not released!"
    }

    # search the query and give results
    search_anime() {
        search_gql="query(        \$search: SearchInput        \$limit: Int        \$page: Int        \$translationType: VaildTranslationTypeEnumType        \$countryOrigin: VaildCountryOriginEnumType    ) {    shows(        search: \$search        limit: \$limit        page: \$page        translationType: \$translationType        countryOrigin: \$countryOrigin    ) {        edges {            _id name availableEpisodes __typename       }    }}"

        curl -e "https://${allanime_base}" -s --cipher "AES256-SHA256" -G "https://api.${allanime_base}/allanimeapi" --data-urlencode "variables={\"search\":{\"allowAdult\":false,\"allowUnknown\":false,\"query\":\"$1\"},\"limit\":40,\"page\":1,\"translationType\":\"$mode\",\"countryOrigin\":\"ALL\"}" --data-urlencode "query=$search_gql" -A "$agent" | sed 's|Show|\n|g' | sed -nE "s|.*_id\":\"([^\"]*)\",\"name\":\"([^\"]*)\".*${mode}\":([1-9][^,]*).*|\1\t\2 (\3 episodes)|p"
    }

    # get the episodes list of the selected anime
    episodes_list() {
        episodes_list_gql="query (\$showId: String!) {    show(        _id: \$showId    ) {        _id availableEpisodesDetail    }}"

        curl -e "https://${allanime_base}" -s --cipher AES256-SHA256 -G "https://api.${allanime_base}/allanimeapi" --data-urlencode "variables={\"showId\":\"$*\"}" --data-urlencode "query=$episodes_list_gql" -A "$agent" | sed -nE "s|.*$mode\":\[([0-9.\",]*)\].*|\1|p" | sed 's|,|\n|g; s|"||g' | sort -n -k 1
    }

    # PLAYING

    process_hist_entry() {
        ep_list=$(episodes_list "$id")
        ep_no=$(printf "%s" "$ep_list" | sed -n "/^${ep_no}$/{n;p;}") 2>/dev/null
        [ -n "$ep_no" ] && printf "%s\t%s - episode %s\n" "$id" "$title" "$ep_no"
    }

    update_history() {
        if grep -q -- "$id" "$histfile"; then
            sed -E "s/^[^\t]+\t${id}\t/${ep_no}\t${id}\t/" "$histfile" >"${histfile}.new"
        else
            cp "$histfile" "${histfile}.new"
            printf "%s\t%s\t%s\n" "$ep_no" "$id" "$title" >>"${histfile}.new"
        fi
        mv "${histfile}.new" "$histfile"
    }

    download() {
        case $1 in
        *m3u8*) ffmpeg -loglevel error -stats -i "$1" -c copy "$download_dir/$2.mp4" ;;
        *) if curl -s -m 5 "$1" | grep -q '^#EXTM3U'; then
            ffmpeg -loglevel error -stats -i "$1" -c copy "$download_dir/$2.mp4"
        else
            if uname -a | grep -q "ish"; then
                curl --output-dir "$download_dir" -o "$2.mp4" "$1"
            else
                aria2c --check-certificate=false --continue --summary-interval=0 -x 16 -s 16 "$1" --dir="$download_dir" -o "$2.mp4" --download-result=hide
            fi
        fi ;;
        esac
    }

    play_episode() {
        [ -z "$episode" ] && get_episode_url
        case "$player_function" in
        debug) printf "All links:\n%s\nSelected link:\n%s\n" "$links" "$episode" ;;
        mpv*) nohup "$player_function" --force-media-title="${allanime_title}episode-${ep_no}-${mode}" "$episode" >/dev/null 2>&1 &;;
        android_mpv) nohup am start --user 0 -a android.intent.action.VIEW -d "$episode" -n is.xyz.mpv/.MPVActivity >/dev/null 2>&1 &;;
        android_vlc) nohup am start --user 0 -a android.intent.action.VIEW -d "$episode" -n org.videolan.vlc/org.videolan.vlc.gui.video.VideoPlayerActivity -e "title" "${allanime_title}episode-${ep_no}-${mode}" >/dev/null 2>&1 &;;
        iina) nohup "$player_function" --no-stdin --keep-running --mpv-force-media-title="${allanime_title}episode-${ep_no}-${mode}" "$episode" >/dev/null 2>&1 &;;
        flatpak_mpv) flatpak run io.mpv.Mpv --force-media-title="${allanime_title}episode-${ep_no}-${mode}" "$episode" >/dev/null 2>&1 &;;
        vlc*) nohup "$player_function" --play-and-exit --meta-title="${allanime_title}episode-${ep_no}-${mode}" "$episode" >/dev/null 2>&1 &;;
        *yncpla*) nohup "$player_function" "$episode" -- --force-media-title="${allanime_title}episode-${ep_no}-${mode}" >/dev/null 2>&1 &;;
        download) "$player_function" "$episode" "${allanime_title}episode-${ep_no}-${mode}" ;;
        catt) nohup catt cast "$episode" >/dev/null 2>&1 &;;
        iSH)
            printf "\e]8;;vlc-x-callback://x-callback-url/stream?url=%s&filename=%sepisode-%s-%s\a~~~~~~~~~~~~~~~~~~~~\n~ Tap to open VLC ~\n~~~~~~~~~~~~~~~~~~~~\e]8;;\a\n" "$episode" "$allanime_title" "$ep_no" "$mode"
            sleep 5
            ;;
        *) nohup "$player_function" "$episode" >/dev/null 2>&1 &;;
        esac
        replay="$episode"
        unset episode
        update_history
        if [ "$no_menu" -eq 1 ]; then
            printf "\33[2K\r\033[1;34mPlaying episode %s...\033[0m\n" "$ep_no of $title"
            exit 0
        fi
        wait
    }

    play() {
        start=$(printf "%s" "$ep_no" | grep -Eo '^(-1|[0-9]+(\.[0-9]+)?)')
        end=$(printf "%s" "$ep_no" | grep -Eo '(-1|[0-9]+(\.[0-9]+)?)$')
        [ "$start" = "-1" ] && ep_no=$(printf "%s" "$ep_list" | tail -n1) && unset start
        [ -z "$end" ] || [ "$end" = "$start" ] && unset start end
        [ "$end" = "-1" ] && end=$(printf "%s" "$ep_list" | tail -n1)
        line_count=$(printf "%s\n" "$ep_no" | wc -l | tr -d "[:space:]")
        if [ "$line_count" != 1 ] || [ -n "$start" ]; then
            [ -z "$start" ] && start=$(printf "%s\n" "$ep_no" | head -n1)
            [ -z "$end" ] && end=$(printf "%s\n" "$ep_no" | tail -n1)
            range=$(printf "%s\n" "$ep_list" | sed -nE "/^${start}\$/,/^${end}\$/p")
            [ -z "$range" ] && die "Invalid range!"
            for i in $range; do
                tput clear
                ep_no=$i
                printf "\33[2K\r\033[1;34mPlaying episode %s...\033[0m\n" "$ep_no"
                play_episode
            done
        else
            play_episode
        fi
    }

    agent="Mozilla/5.0 (Windows NT 6.1; Win64; rv:109.0) Gecko/20100101 Firefox/109.0"
    allanime_base="allanime.to"
    mode="${ANI_CLI_MODE:-sub}"
    download_dir="${ANI_CLI_DOWNLOAD_DIR:-.}"
    quality="${ANI_CLI_QUALITY:-best}"
    no_menu=0
    case "$(uname -a)" in
    *Darwin*) player_function="${ANI_CLI_PLAYER:-iina}" ;;           # mac OS
    *ndroid*) player_function="${ANI_CLI_PLAYER:-android_mpv}" ;;    # Android OS (termux)
    *steamdeck*) player_function="${ANI_CLI_PLAYER:-flatpak_mpv}" ;; # steamdeck OS
    *MINGW*) player_function="${ANI_CLI_PLAYER:-mpv.exe}" ;;         # Windows OS
    *ish*) player_function="${ANI_CLI_PLAYER:-iSH}" ;;               # iOS (iSH)
    *) player_function="${ANI_CLI_PLAYER:-mpv}" ;;                   # Linux OS
    esac

    use_external_menu="${ANI_CLI_EXTERNAL_MENU:-0}"
    [ -t 0 ] || use_external_menu=1
    [ "$use_external_menu" = "0" ] && multi_selection_flag="${ANI_CLI_MULTI_SELECTION:-"-m"}"
    [ "$use_external_menu" = "1" ] && multi_selection_flag="${ANI_CLI_MULTI_SELECTION:-"-multi-select"}"
    cache_dir="${ANI_CLI_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/media-cli}"
    [ ! -d "$cache_dir" ] && mkdir -p "$cache_dir"
    hist_dir="${ANI_CLI_HIST_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/media-cli}"
    [ ! -d "$hist_dir" ] && mkdir -p "$hist_dir"
    histfile="$hist_dir/ani-hsts"
    [ ! -f "$histfile" ] && : >"$histfile"
    search="${ANI_CLI_DEFAULT_SOURCE:-scrape}"

    printf "\33[2K\r\033[1;34mChecking dependencies...\033[0m\n"
    dep_ch "curl" "sed" "grep" "fzf" || true
    case "$player_function" in
    debug) ;;
    download) dep_ch "ffmpeg" "aria2c" ;;
    flatpak*)
        dep_ch "flatpak"
        flatpak info io.mpv.Mpv >/dev/null 2>&1 || die "Program \"mpv (flatpak)\" not found. Please install it."
        ;;
    android*) printf "Checking of players on Android is disabled\n" ;;
    *iSH*) printf "Checking of players on iOS is disabled\n" ;;
    *) dep_ch "$player_function" ;;
    esac

    while [ $# -gt 0 ]; do
        case "$1" in
        -v | --vlc)
            case "$(uname -a)" in
            *ndroid*) player_function="android_vlc" ;;
            MINGW*) player_function="vlc.exe" ;;
            *iSH*) player_function="iSH" ;;
            *) player_function="vlc" ;;
            esac
            ;;
        -s | --syncplay)
            case "$(uname -s)" in
            Darwin*) player_function="/Applications/Syncplay.app/Contents/MacOS/syncplay" ;;
            MINGW* | *Msys) player_function="/c/Program Files (x86)/Syncplay/Syncplay.exe" ;;
            *) player_function="syncplay" ;;
            esac
            ;;
        -q | --quality)
            [ $# -lt 2 ] && die "missing argument!"
            quality="$2"
            shift
            ;;
        -S | --select-nth)
            [ $# -lt 2 ] && die "missing argument!"
            index="$2"
            shift
            ;;
        -c | --continue) search=history ;;
        -d | --download) player_function=download ;;
        -D | --delete)
            : >"$histfile"
            exit 0
            ;;
        -V | --version) version_info ;;
        -h | --help) help_info ;;
        -e | --episode | -r | --range)
            [ $# -lt 2 ] && die "missing argument!"
            ep_no="$2"
            shift
            ;;
        -N | --non-interactive) no_menu=1 ;;
        --dub) mode="dub" ;;
        *) query="$(printf "%s" "$query $1" | sed "s|^ ||;s| |+|g")" ;;
        esac
        shift
    done

    # searching
    case "$search" in
    history)
        anime_list=$(while read -r ep_no id title; do
            process_hist_entry &
            wait
        done <"$histfile")
        [ -z "$anime_list" ] && die "No unwatched series in history!"
        result=$(printf "%s" "$anime_list" | nl -w 1 | nth "Select anime: " | cut -f1)
        [ -z "$result" ] && exit 1
        resfile="$(mktemp)"
        grep "$result" "$histfile" >"$resfile"
        read -r ep_no id title <"$resfile"
        ep_list=$(episodes_list "$id")
        ep_no=$(printf "%s" "$ep_list" | sed -n "/^${ep_no}$/{n;p;}") 2>/dev/null
        allanime_title="$(printf "%s" "$title" | cut -d'(' -f1 | tr -d '[:punct:]' | tr 'A-Z ' 'a-z-')"
        tput cuu1 && tput el
        ;;
    *)
        while [ -z "$query" ]; do
            if [ "$use_external_menu" = "0" ]; then
                printf "Search anime: " && read -r query
            else
                query=$(: | external_menu "" "Search anime: ")
            fi
        done
        query=$(printf "%s" "$query" | sed "s| |+|g")
        anime_list=$(search_anime "$query")
        [ -z "$anime_list" ] && die "No results found!"
        [ "$index" -eq "$index" ] 2>/dev/null && result=$(printf "%s" "$anime_list" | sed -n "${index}p")
        [ -z "$index" ] && result=$(printf "%s" "$anime_list" | nl -w 1 | nth "Select anime: ")
        [ -z "$result" ] && exit 1
        title=$(printf "%s" "$result" | cut -f2)
        allanime_title="$(printf "%s" "$title" | cut -d'(' -f1 | tr -d '[:punct:]' | tr 'A-Z ' 'a-z-')"
        id=$(printf "%s" "$result" | cut -f1)
        ep_list=$(episodes_list "$id")
        [ -z "$ep_no" ] && ep_no=$(printf "%s" "$ep_list" | nth "Select episode: " "$multi_selection_flag")
        [ -z "$ep_no" ] && exit 1
        ;;
    esac

    # moves the cursor up one line and clears that line
    tput cuu1 && tput el

    # playback & loop
    play
    [ "$player_function" = "download" ] || [ "$player_function" = "debug" ] && exit 0

    while cmd=$(printf "next\nreplay\nprevious\nselect\nchange_quality\nquit" | nth "Playing episode $ep_no of $title... "); do
        case "$cmd" in
        next) ep_no=$(printf "%s" "$ep_list" | sed -n "/^${ep_no}$/{n;p;}") 2>/dev/null ;;
        replay) episode="$replay" ;;
        previous) ep_no=$(printf "%s" "$ep_list" | sed -n "/^${ep_no}$/{g;1!p;};h") 2>/dev/null ;;
        select) ep_no=$(printf "%s" "$ep_list" | nth "Select episode: " "$multi_selection_flag") ;;
        change_quality)
            episode=$(printf "%s" "$links" | sed -n '/^\([0-9]*p\)/p' | launcher)
            quality=$(printf "%s" "$episode" | grep -oE "^[0-9]+")
            episode=$(printf "%s" "$episode" | cut -d'>' -f2)
            ;;
        *) exit 0 ;;
        esac
        [ -z "$ep_no" ] && die "Out of range"
        play
    done

}

drama_query() {
    # Handle drama queries here

    # shift $((OPTIND - 1))
    # query="$@"

    version_text() {
        inf "Version: $VERSION" >&2
    }

    die() {
        err "$*"
        exit 1
    }

    # checks if dependencies are present
    dep_ch() {
        for dep; do
            if ! command -v "$dep" >/dev/null; then
                err "Program \"$dep\" not found. Please install it."
                #aria2c is in the package aria2
                [ "$dep" = "aria2c" ] && err "To install aria2c, Type <your_package_manager> aria2"
                die
            fi
        done
    }

    download() {
        case $2 in
        *m3u8*)
            ffmpeg -loglevel error -stats -referer "$1" -i "$2" -c copy "$download_dir/${3}${4}.mp4"
            ;;
        *)
            aria2c --summary-interval=0 -x 16 -s 16 --referer="$1" "$2" --dir="$download_dir" -o "${3}${4}.mp4" --download-result=hide
            ;;
        esac
    }

    #############
    # SEARCHING #
    #############

    # gets drama names along with its id for search term
    search_drama() {
        search=$(printf '%s' "$1" | tr ' ' '-')
        curl -s "$base_url/search.html?keyword=$search" |
            sed -nE 's_^[[:space:]]*<a href="/videos/([^"]*)">_\1_p'
    }

    check_episode() {
        curl -s "$base_url/videos/$1" | sed '/Latest Episodes/,$d' | sed -nE "s_^[[:space:]]*<a href.*videos/${2}(.*)\">_\1_p"
    }

    process_hist_entry() {
        temp_drama_id=$(printf "%s" "$drama_id" | sed 's/[0-9]*.$//')
        latest_ep=$(printf "%s" "$drama_id" | sed "s/$temp_drama_id//g")
        current_ep=$(check_episode "$drama_id" "$temp_drama_id" | head -n 1)
        if [ -n "$current_ep" ] && [ "$current_ep" -ge "$latest_ep" ]; then
            printf "%s\n" "$drama_id"
        fi
    }

    # compares history with asianembed, only shows unfinished drama
    search_history() {
        tput clear
        [ ! -s "$logfile" ] && die "History is empty"
        search_results=$(
            while read -r drama_id; do process_hist_entry &;done <"$logfile"
            wait
        )
        [ -z "$search_results" ] && die "No unwatched episodes"
        one_hist=$(printf '%s\n' "$search_results" | grep -e "$" -c)
        [ "$one_hist" = 1 ] && select_first=1
        drama_selection "$search_results"
        ep_choice_start=$(sed -n -E "s/${selection_id}(.*)/\1/p" "$logfile")
    }

    ##################
    # URL PROCESSING #
    ##################

    # get the download page url
    get_dpage_link() {
        drama_id="$1"
        ep_no="$2"

        curl -s "$base_url/videos/${drama_id}${ep_no}" | sed -nE 's_^[[:space:]]*<iframe src="([^"]*)".*_\1_p' |
            sed 's/^/https:/g'
    }

    decrypt_link() {
        fembed_id=$(curl -A "uwu" -s "$1" | sed -nE 's_.*fembed.*/v/([^#]*).*_\1_p')
        [ -z "$fembed_id" ] || video_links=$(curl -A "uwu" -s -X POST "https://fembed9hd.com/api/source/$fembed_id" -H "x-requested-with:XMLHttpRequest" | sed -e 's/\\//g' -e 's/.*data"://' | tr "}" "\n" | sed -nE 's/.*file":"(.*)","label":"([^"]*)".*/\2>\1/p')
        [ -z "$video_links" ] || return 0
        secret_key='3933343232313932343333393532343839373532333432393038353835373532'
        iv='39323632383539323332343335383235'
        ajax_url="$base_url/encrypt-ajax.php"
        ajax=$(printf "%s" "$1" | sed -nE 's/.*id=([^&]*)&.*/\1/p' | openssl enc -e -aes256 -K "$secret_key" -iv "$iv" -a)
        video_links=$(curl -s -H "X-Requested-With:XMLHttpRequest" "$ajax_url" -d "id=$ajax" | sed -e 's/{"data":"//' -e 's/"}/\n/' -e 's/\\//g' | base64 -d | openssl enc -d -aes256 -K "$secret_key" -iv "$iv" | sed -e 's/\].*/\]/' -e 's/\\//g' | tr '{|}' '\n' | sed -nE 's/\"file\":"([^"]*)".*label.*P.*/\1/p')
    }

    # chooses the link for the set quality
    get_video_quality() {
        dpage_url="$1"
        decrypt_link "$dpage_url"
        case $quality in
        best)
            video_link=$(printf '%s' "$video_links" | head -n 4 | tail -n 1 | cut -d'>' -f2)
            ;;
        worst)
            video_link=$(printf '%s' "$video_links" | head -n 1 | cut -d'>' -f2)
            ;;
        *)
            video_link=$(printf '%s' "$video_links" | grep -i "${quality}p" | head -n 1 | cut -d'>' -f2)
            if [ -z "$video_link" ]; then
                err "Current video quality is not available (defaulting to best quality)"
                quality=best
                video_link=$(printf '%s' "$video_links" | head -n 4 | tail -n 1 | cut -d'>' -f2)
            fi
            ;;
        esac
        printf '%s' "$video_link"
    }

    ###############
    # TEXT OUTPUT #
    ###############

    # display an error message to stderr (in red)
    err() {
        printf "\033[1;31m%s\033[0m\n" "$*" >&2
    }

    # display an informational message (first argument in green, second in magenta)
    inf() {
        printf "\033[1;35m%s \033[1;35m%s\033[0m\n" "$1" "$2"
    }

    # prompts the user with message in $1-2 ($1 in blue, $2 in magenta) and saves the input to the variables in $REPLY and $REPLY2
    prompt() {
        printf "\033[1;35m%s\033[1;35m%s\033[1;34m\033[0m" "$1" "$2"
        read -r REPLY REPLY2
    }

    # displays an even (cyan) line of a menu line with $2 as an indicator in () and $1 as the option
    menu_line_even() {
        printf "\033[1;36m(\033[1;36m%s\033[1;36m) \033[1;36m%s\033[0m\n" "$2" "$1"
    }

    # displays an odd (yellow) line of a menu line with $2 as an indicator in () and $1 as the option
    menu_line_odd() {
        printf "\033[1;33m(\033[1;33m%s\033[1;33m) \033[1;33m%s\033[0m\n" "$2" "$1"
    }

    # display alternating menu lines (even and odd)
    menu_line_alternate() {
        menu_line_parity=${menu_line_parity:-0}
        if [ "$menu_line_parity" -eq 0 ]; then
            menu_line_odd "$1" "$2"
            menu_line_parity=1
        else
            menu_line_even "$1" "$2"
            menu_line_parity=0
        fi
    }

    # displays a warning (red) line of a menu line with $2 as an indicator in [] and $1 as the option
    menu_line_strong() {
        printf "\033[1;31m(\033[1;31m%s\033[1;31m) \033[1;31m%s\033[0m\n" "$2" "$1"
    }

    #################
    # INPUT PARSING #
    #################

    # only lets the user pass in case of a valid search
    process_search() {
        search_results=$(search_drama "$query")
        while [ -z "$search_results" ]; do
            err 'No search results found'
            prompt 'Search Drama: '
            query="$REPLY $REPLY2"
            search_results=$(search_drama "$query")
        done
        drama_selection "$search_results"
        episode_selection
    }

    #drama-selection menu handling function
    drama_selection() {
        count=1
        while read -r drama_id; do
            menu_line_alternate "$drama_id" "$count"
            : $((count += 1))
        done <<-EOF
	$search_results
	EOF
        if [ -n "$select_first" ]; then
            tput clear
            choice=1
        elif [ -z "$ep_choice_to_start" ] || { [ -n "$ep_choice_to_start" ] && [ -z "$select_first" ]; }; then
            menu_line_strong "exit" "q"
            prompt "> "
            choice="$REPLY"
            while ! [ "$choice" -eq "$choice" ] 2>/dev/null || [ "$choice" -lt 1 ] || [ "$choice" -ge "$count" ] || [ "$choice" = " " ]; do
                [ "$choice" = "q" ] && exit 0
                err "Invalid choice entered"
                prompt "> "
                choice="$REPLY"
            done
        fi
        # Select respective drama_id
        selection_id="$(printf "%s" "$search_results" | sed -n "${choice}p")"
        temp_drama_id=$(printf "%s" "$selection_id" | sed 's/[0-9]*.$//')
        select_ep_result=$(check_episode "$selection_id" "$temp_drama_id")
        last_ep_number=$(printf "%s" "$select_ep_result" | head -n 1)
        first_ep_number=$(printf "%s" "$select_ep_result" | tail -n 1)
        selection_id=$temp_drama_id
    }

    # gets episode number from user, makes sure it's in range, skips input if only one episode exists
    episode_selection () {
        if [ "$last_ep_number" -gt "$first_ep_number" ]; then
            if [ -z "$ep_choice_to_start" ]; then
                # if branches, because order matters this time
                while : ; do
                    inf "To specify a range, use: start_number end_number"
                    inf "Episodes:" "($first_ep_number-$last_ep_number)"
                    prompt "> "
                    ep_choice_start="$REPLY"
                    ep_choice_end="$REPLY2"
                    if [ "$REPLY" = q ]; then
                        exit 0
                    fi
                    [ "$ep_choice_end" = "-1" ] && ep_choice_end="$last_ep_number"
                    if ! [ "$ep_choice_start" -eq "$ep_choice_start" ] 2>/dev/null || { [ -n "$ep_choice_end" ] && ! [ "$ep_choice_end" -eq "$ep_choice_end" ] 2>/dev/null; }; then
                        err "Invalid number(s)"
                        continue
                    fi
                    if [ "$ep_choice_start" -gt "$last_ep_number" ] 2>/dev/null || [ "$ep_choice_end" -gt "$last_ep_number" ] 2>/dev/null || [ "$ep_choice_start" -lt "$first_ep_number" ] 2>/dev/null; then
                        err "Episode out of range"
                        continue
                    fi
                    if [ "$ep_choice_end" -le "$ep_choice_start" ]; then
                        err "Invalid range"
                        continue
                    fi
                    break
                done
            else
                ep_choice_start="$ep_choice_to_start" && unset ep_choice_to_start
            fi
        else
            # In case the drama contains only a single episode
            ep_choice_start=1
        fi
        if [ -z "$ep_choice_end" ]; then
            auto_play=0
        else
            auto_play=1
        fi
    }

    # creates $episodes from $ep_choice_start and $ep_choice_end
    generate_ep_list() {
        episodes=$ep_choice_start
        [ -n "$ep_choice_end" ] && episodes=$(seq "$ep_choice_start" "$ep_choice_end")
    }


    ##################
    # VIDEO PLAYBACK #
    ##################

    append_history () { # todo: unite this with the temporary histfile writing
        grep -q "${selection_id}" "$logfile" || printf "%s%s\n" "$selection_id" $((episode+1)) >> "$logfile"
    }

    # opens selected episodes one-by-one
    open_selection() {
        for ep in $episodes; do
            open_episode "$selection_id" "$ep"
        done
        episode=${ep_choice_end:-$ep_choice_start}
    }

    open_episode () {
        drama_id="$1"
        episode="$2"

        tput clear
        inf "Loading episode $episode..."
        # decrypting url
        dpage_link=$(get_dpage_link "$drama_id" "$episode")
        echo "$dpage_link"
            video_url=$(get_video_quality "$dpage_link")
        echo "$video_url"
        if [ "$is_download" -eq 0 ]; then
            # write drama and episode number and save to temporary history
            sed -E "
                s/^${selection_id}[0-9]*/${selection_id}$((episode+1))/
            " "$logfile" > "${logfile}.new"
            [ ! "$PID" = "0" ] && kill "$PID" >/dev/null 2>&1
            [ -z "$video_url" ] && die "Video URL not found"
            play_episode
            # overwrite history with temporary history
            mv "${logfile}.new" "$logfile"
        else
            mkdir -p "$download_dir"
            inf "Downloading episode $episode ..."
            episode=$(printf "%03d" "$episode")
            {
                if download "$dpage_link" "$video_url" "$drama_id" "$episode" ; then
                    inf "Downloaded episode: $episode"
                else
                    err "Download failed episode: $episode , please retry or check your internet connection"
                fi
            }
        fi
    }

    play_episode () {
        # Build command
        set -- "$player_fn" "$video_url"
        case "$player_fn" in
            vlc)
                [ ! "$auto_play" -eq 0 ] && set -- "$@" "--play-and-exit"
                set -- "$@" --http-referrer="$dpage_link"
                ;;
            *)
                set -- "$@" --referrer="$dpage_link" --force-media-title="${drama_id}${episode}"
                ;;
        esac
        # Run Command
        if [ "$auto_play" -eq 0 ]; then
            nohup "$@" > /dev/null 2>&1 &
        else
            inf "Currently playing $display_name episode" "$episode/$last_ep_number, Range: $ep_choice_start-$ep_choice_end"
            "$@" > /dev/null 2>&1
            sleep 2
        fi
        PID=$!
    }

    ############
    # START UP #
    ############

    # clears the colors and deletes temporary logfile when exited using SIGINT
    trap 'printf "\033[0m";[ -f "$logfile".new ] && rm "$logfile".new;exit 1' INT HUP

    # default options
    player_fn="mpv" #video player needs to be able to play urls
    is_download=0
    PID=0
    quality=best
    scrape=query
    download_dir="."
    choice=
    auto_play=0
    # history file path
    logfile="${XDG_CACHE_HOME:-$HOME/.cache}/dra-hsts"
    logdir="${XDG_CACHE_HOME:-$HOME/.cache}"

    # create history file and history dir if none found
    [ -d "$logdir" ] || mkdir "$logdir"
    [ -f "$logfile" ] || : > "$logfile"

    while getopts 'vq:dp:chDUVa:' OPT; do
        case $OPT in
            d)
                is_download=1
                ;;
            a)
                ep_choice_to_start=$OPTARG
                ;;
            D)
                : > "$logfile"
                exit 0
                ;;
            p)
                is_download=1
                download_dir=$OPTARG
                ;;
            q)
                quality=$OPTARG
                ;;
            c)
                scrape=history
                ;;
            v)
                player_fn="vlc"
                ;;
            V)
                version_text
                exit 0
                ;;
            *)
                help_text
                exit 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    dep_ch "curl" "sed" "grep" "openssl"
    if [ "$is_download" -eq 0 ]; then
        dep_ch "$player_fn"
    else
        dep_ch "aria2c" "ffmpeg"
    fi

    base_url="https://asianhdplay.pro"
    case $scrape in
        query)
            if [ -z "$*" ]; then
                prompt "Search Drama: "
                query="$REPLY $REPLY2"
            else
                if [ -n "$ep_choice_to_start" ]; then
                    REPLY=1
                    select_first=1
                fi
                query="$*"
            fi
            process_search
            ;;
        history)
            search_history
            [ "$REPLY" = "q" ] && exit 0
            first_ep_number=$(check_episode "${selection_id}1" "$selection_id" | tail -1)
            ;;
        *)
            die "Unexpected scrape type"
    esac

    generate_ep_list
    append_history
    open_selection

    ########
    # LOOP #
    ########

    while :; do
    if [ -z "$select_first" ]; then
        if [ "$auto_play" -eq 0 ]; then
            display_name=$(printf '%s' "$selection_id" | sed 's/-episode-//')
            inf "Currently playing $display_name episode" "$episode/$last_ep_number"
        else
            auto_play=0
        fi
        [ "$episode" -ne "$last_ep_number" ] && menu_line_alternate 'next' 'n'
        [ "$episode" -ne "$first_ep_number" ] && menu_line_alternate 'previous' 'p'
        menu_line_alternate "replay" "r"
        [ "$last_ep_number" -ne "$first_ep_number" ] && menu_line_alternate 'select' 's'
        menu_line_strong "exit" "q"
        prompt "> "
        choice="$REPLY"
        case $choice in
            n)
                ep_choice_start=$((episode + 1))
                unset ep_choice_end
                ;;
            p)
                ep_choice_start=$((episode - 1))
                unset ep_choice_end
                ;;
            r)
                ep_choice_start="$episode"
                unset ep_choice_end
                ;;
            s)
                episode_selection
                ;;
            q)
                break
                ;;
            *)
                tput clear
                err "Invalid choice"
                continue
                ;;
        esac
        generate_ep_list
        append_history
        open_selection
    else
        wait $!
        exit
    fi
    done

}

help_info() {
    if [ "$1" = "anime" ]; then
        printf "
        Anime Usage:
        %s [options] [query]
        %s [query] [options]
        %s [options] [query] [options]

        Options:
          -c, --continue
            Continue watching from history
          -d, --download
            Download the video instead of playing it
          -D, --delete
            Delete history
          -s, --syncplay
            Use Syncplay to watch with friends
          -S, --select-nth
            Select nth entry
          -q, --quality
            Specify the video quality
          -v, --vlc
            Use VLC to play the video
          -V, --version
            Show the version of the script
          -h, --help
            Show this help message and exit
          -e, --episode, -r, --range
            Specify the number of episodes to watch
          --dub
            play dubbed version
          -N, --non-interactive
            Disable the interactive menu
        Some example usages:
          %s anime -q 720p banana fish
          %s anime -d -e 2 cyberpunk edgerunners
          %s anime --vlc cyberpunk edgerunners -q 1080p -e 4
          %s anime blue lock -e 5-6
          %s anime -e \"5 6\" blue lock
        \n" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}"
    elif [ "$1" = "drama" ]; then
        printf "
        Drama Usage:
          %s [-v] [-q <quality>] [-a <episode>] [-d | -p <download_dir>] [<query>]
          %s [-v] [-q <quality>] -c
          %s -h | -D | -U | -V

        Options:
          -c continue watching drama from history
          -a specify episode to watch
          -h show helptext
          -d download episode
          -p download episode to specified directory
          -q set video quality (best|worst|360|480|720|1080)
          -v use VLC as the media player
          -D delete history
          -V print version number and exit

        Episode selection:
          Multiple episodes can be chosen given a range
            Choose episode [1-13]: 1 6
            This would choose episodes 1 2 3 4 5 6
            To select the last episode use -1

          When selecting non-interactively, the first result will be
          selected, if drama is passed
        \n" "${0##*/}" "${0##*/}" "${0##*/}"
    else
        printf "
        Media CLI Usage:
            %s [options] [query]
            %s [query] [options]
            %s [options] [query] [options]

        Options:
        -a, --anime
            Watch anime
        -d, --drama
            Watch drama
        -u, --update
            Update
        -h, --help
            Show this help message and exit

        Subcommands:
        $(help_info anime | sed 's/^/  /')
        $(help_info drama | sed 's/^/  /')
        " "${0##*/}" "${0##*/}" "${0##*/}"
    fi
    exit 0
}

if [ $# -lt 1 ]; then
    help_info
    exit 1
fi

update_script() {
  update="$(curl -s -A "$agent" "https://raw.githubusercontent.com/Caivy/media-cli/main/media-cli.sh")" || die "Connection error"
  update="$(printf '%s\n' "$update" | diff -u "$0" -)"
  if [ -z "$update" ]; then
    printf "Script is up to date :)\n"
  else
    if printf '%s\n' "$update" | patch "$0" -; then
      printf "Script has been updated\n"
    else
      die "Can't update for some reason!"
    fi
  fi
  exit 0
}

# Check if update flag is provided
if [[ "$1" == "-u" || "$1" == "--update" ]]; then
  update_script
fi

# Parse the first argument and call the appropriate query function
case "$1" in
anime) anime_query "${@:2}" ;;
drama) drama_query "${@:2}" ;;
*) help_info ;;
esac

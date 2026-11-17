//! 起動引数の解釈（壁紙・スクリーンセーバー・プレビュー・設定画面）

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LaunchMode {
    Settings,
    Wallpaper,
    Screensaver,
    Preview,
}

pub fn parse_mode<I, S>(args: I) -> LaunchMode
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let items: Vec<String> = args.into_iter().map(|s| s.as_ref().to_string()).collect();
    if items.iter().any(|a| a == "--wallpaper") {
        return LaunchMode::Wallpaper;
    }
    let first = items
        .iter()
        .find(|a| (a.starts_with('/') || a.starts_with('-')) && a.len() > 1);
    let Some(arg) = first else {
        return LaunchMode::Settings;
    };
    let token = arg.trim_start_matches('-').trim_start_matches('/').to_ascii_lowercase();
    if token.starts_with('s') {
        LaunchMode::Screensaver
    } else if token.starts_with('p') {
        LaunchMode::Preview
    } else {
        LaunchMode::Settings
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_various_args() {
        assert_eq!(parse_mode(["--wallpaper"]), LaunchMode::Wallpaper);
        assert_eq!(parse_mode(["/s"]), LaunchMode::Screensaver);
        assert_eq!(parse_mode(["/S"]), LaunchMode::Screensaver);
        assert_eq!(parse_mode(["/p", "12345"]), LaunchMode::Preview);
        assert_eq!(parse_mode(["/c"]), LaunchMode::Settings);
        assert_eq!(parse_mode(Vec::<String>::new()), LaunchMode::Settings);
    }
}

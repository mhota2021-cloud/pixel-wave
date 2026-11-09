//起動時の引数の読み取り（スクリーンセーバーとしての起動を判定する）

//起動モード（Settingsは設定画面、Screensaverは全画面表示、Previewはすぐ終了）
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunMode {
    Settings,
    Screensaver,
    Preview,
}

//引数から起動モードを決める（引数argsは実行ファイル名を含む一覧で、/sは全画面、/pはプレビュー、/cと無指定は設定画面）
pub fn parse_mode(args: &[String]) -> RunMode {
    for arg in args.iter().skip(1) {
        let a = arg.trim().to_lowercase();
        if a.starts_with("/s") || a.starts_with("-s") {
            return RunMode::Screensaver;
        }
        if a.starts_with("/p") || a.starts_with("-p") {
            return RunMode::Preview;
        }
        if a.starts_with("/c") || a.starts_with("-c") {
            return RunMode::Settings;
        }
    }
    RunMode::Settings
}

#[cfg(test)]
mod tests {
    use super::*;

    //文字列の一覧を作る（引数itemsは引数の並び）
    fn args(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn 引数なしは設定画面() {
        assert_eq!(parse_mode(&args(&["PixelWave.exe"])), RunMode::Settings);
    }

    #[test]
    fn sはスクリーンセーバー() {
        assert_eq!(
            parse_mode(&args(&["PixelWave.scr", "/s"])),
            RunMode::Screensaver
        );
        assert_eq!(
            parse_mode(&args(&["PixelWave.scr", "/S"])),
            RunMode::Screensaver
        );
    }

    #[test]
    fn cは設定画面() {
        assert_eq!(parse_mode(&args(&["PixelWave.scr", "/c"])), RunMode::Settings);
        assert_eq!(
            parse_mode(&args(&["PixelWave.scr", "/c:1234"])),
            RunMode::Settings
        );
    }

    #[test]
    fn pはプレビュー() {
        assert_eq!(
            parse_mode(&args(&["PixelWave.scr", "/p", "1234"])),
            RunMode::Preview
        );
        assert_eq!(
            parse_mode(&args(&["PixelWave.scr", "/p:1234"])),
            RunMode::Preview
        );
    }
}

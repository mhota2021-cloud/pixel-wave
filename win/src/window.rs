//! Win32 ウィンドウの生成とメッセージディスパッチ

use std::ffi::c_void;

use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CS_HREDRAW, CS_VREDRAW, CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW,
    GWLP_USERDATA, GetWindowLongPtrW, IDC_ARROW, LoadCursorW, LoadIconW, MSG, RegisterClassExW,
    SetWindowLongPtrW, TranslateMessage, WINDOW_EX_STYLE, WINDOW_STYLE, WM_NCCREATE, WNDCLASSEXW,
};
use windows::core::PCWSTR;

use crate::platform::wide_null;

pub trait WindowHandler {
    fn handle_message(&mut self, hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT>;
}

unsafe extern "system" fn wnd_proc<T: WindowHandler>(
    hwnd: HWND,
    msg: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if msg == WM_NCCREATE {
        let cs = unsafe { &*(lparam.0 as *const windows::Win32::UI::WindowsAndMessaging::CREATESTRUCTW) };
        unsafe { SetWindowLongPtrW(hwnd, GWLP_USERDATA, cs.lpCreateParams as isize) };
    }
    let ptr = unsafe { GetWindowLongPtrW(hwnd, GWLP_USERDATA) } as *mut T;
    if !ptr.is_null() {
        let handler = unsafe { &mut *ptr };
        if let Some(res) = handler.handle_message(hwnd, msg, wparam, lparam) {
            return res;
        }
    }
    unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) }
}

pub fn register_and_create<T: WindowHandler>(
    class_name: &str,
    title: &str,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    style: WINDOW_STYLE,
    ex_style: WINDOW_EX_STYLE,
    parent: Option<HWND>,
    handler: &mut T,
) -> HWND {
    let cls_w = wide_null(class_name);
    let title_w = wide_null(title);
    unsafe {
        let hinst = GetModuleHandleW(PCWSTR::null()).unwrap_or_default();
        let icon = LoadIconW(Some(hinst.into()), PCWSTR(1 as *const u16)).unwrap_or_default();
        let wc = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            style: CS_HREDRAW | CS_VREDRAW,
            lpfnWndProc: Some(wnd_proc::<T>),
            hInstance: hinst.into(),
            hIcon: icon,
            hIconSm: icon,
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            lpszClassName: PCWSTR(cls_w.as_ptr()),
            ..Default::default()
        };
        RegisterClassExW(&wc);
        CreateWindowExW(
            ex_style,
            PCWSTR(cls_w.as_ptr()),
            PCWSTR(title_w.as_ptr()),
            style,
            x,
            y,
            w,
            h,
            parent,
            None,
            Some(hinst.into()),
            Some(handler as *mut T as *const c_void),
        )
        .expect("CreateWindowExW failed")
    }
}

/// 汎用メッセージループを回す
pub fn run_message_loop() {
    unsafe {
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}

/// モーダルウィンドウ用（特定ウィンドウが生きている間だけ回す）
pub fn run_modal_loop(hwnd: HWND) {
    unsafe {
        let mut msg = MSG::default();
        while windows::Win32::UI::WindowsAndMessaging::IsWindow(Some(hwnd)).as_bool()
            && GetMessageW(&mut msg, None, 0, 0).as_bool()
        {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}

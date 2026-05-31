import flet as ft

from main import main


app = ft.run(main, assets_dir="assets", export_asgi_app=True)

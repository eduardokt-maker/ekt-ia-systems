import 'package:web/web.dart' as web;

bool openExternalLink(String url) {
  web.window.open(url, '_blank');
  return true;
}

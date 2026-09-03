# Wersja

0.3.0

---

Tu stoi numer wydania. Zmiana tej liczby i scalenie do `master` to jedyny
sposób, żeby powstało nowe wydanie — [`.github/workflows/wydanie.yml`](.github/workflows/wydanie.yml)
rusza wyłącznie wtedy, gdy w scalanych zmianach był ten plik.

Numer trzyma się schematu `główna.poboczna.poprawka`. Workflow czyta pierwszą
linię, która składa się wyłącznie z takiej liczby, więc reszta pliku może być
dowolna.

Numer musi się zgadzać z `version:` w `app/pubspec.yaml` (stamtąd biorą się
`versionName` i `versionCode` Androida). Pilnuje tego workflow, ale ręcznie
i tak nie trzeba tego robić:

```
cd app
python tool/wersja.py 0.2.0
```

Skrypt podnosi numer w obu plikach i zwiększa numer builda w `pubspec.yaml`,
bo Android nie przyjmie aktualizacji z numerem mniejszym lub równym
poprzedniemu.

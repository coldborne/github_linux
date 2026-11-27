<?php
// 1. Подключаемся к базе: настройки лежат в config.php, вне папки public/
$config = require __DIR__ . '/../config.php';
$dsn = 'mysql:host=' . $config['host'] . ';dbname=' . $config['dbname'] . ';charset=utf8mb4';
$pdo = new PDO($dsn, $config['user'], $config['pass']);

// 2. Пришла форма (POST): сохраняем отзыв и возвращаемся на главную
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $stmt = $pdo->prepare('INSERT INTO guests (name, message) VALUES (:name, :message)');
    $stmt->execute([
        'name'    => trim($_POST['name'] ?? ''),
        'message' => trim($_POST['message'] ?? ''),
    ]);
    header('Location: /');
    exit;
}

// 3. Читаем отзывы, новые сверху
$rows = $pdo->query('SELECT name, message, created_at FROM guests ORDER BY id DESC')->fetchAll();
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <title>Отзывы клиентов ТехноСклад</title>
</head>
<body>
    <h1>Отзывы клиентов ООО «ТехноСклад»</h1>
    <p>Администратор: <?= htmlspecialchars($config['admin']) ?></p>
    <p>Сервер: <?= htmlspecialchars($_SERVER['SERVER_SOFTWARE'] ?? '?') ?>, PHP: <?= PHP_SAPI ?></p>

    <form method="post" action="/">
        <input name="name" placeholder="Ваше имя" required>
        <textarea name="message" placeholder="Ваш отзыв" required></textarea>
        <button>Отправить</button>
    </form>

    <p>Отзывов: <?= count($rows) ?></p>
    <?php foreach ($rows as $row): ?>
        <p><b><?= htmlspecialchars($row['name']) ?></b> (<?= $row['created_at'] ?>):
           <?= htmlspecialchars($row['message']) ?></p>
    <?php endforeach; ?>
</body>
</html>

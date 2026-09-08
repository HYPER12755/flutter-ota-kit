import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const int _gridSize = 20;
  static const Duration _gameSpeed = Duration(milliseconds: 150);

  List<Offset> _snake = [const Offset(10, 10)];
  Offset _food = const Offset(5, 5);
  Direction _direction = Direction.right;
  bool _isPlaying = false;
  bool _isGameOver = false;
  int _score = 0;
  int _highScore = 0;
  Timer? _timer;
  final Random _random = Random();
  Offset? _swipeStart;

  @override
  void initState() {
    super.initState();
    _resetGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetGame() {
    _snake = [const Offset(10, 10)];
    _direction = Direction.right;
    _isPlaying = false;
    _isGameOver = false;
    _score = 0;
    _timer?.cancel();
    _spawnFood();
  }

  void _spawnFood() {
    Offset newFood;
    do {
      newFood = Offset(
        _random.nextInt(_gridSize).toDouble(),
        _random.nextInt(_gridSize).toDouble(),
      );
    } while (_snake.contains(newFood));
    _food = newFood;
  }

  void _startGame() {
    if (_isPlaying) return;
    _isPlaying = true;
    _timer = Timer.periodic(_gameSpeed, (timer) {
      _moveSnake();
    });
  }

  void _moveSnake() {
    if (!_isPlaying) return;

    final head = _snake.first;
    Offset newHead;

    switch (_direction) {
      case Direction.up:
        newHead = Offset(head.dx, head.dy - 1);
      case Direction.down:
        newHead = Offset(head.dx, head.dy + 1);
      case Direction.left:
        newHead = Offset(head.dx - 1, head.dy);
      case Direction.right:
        newHead = Offset(head.dx + 1, head.dy);
    }

    if (newHead.dx < 0 ||
        newHead.dx >= _gridSize ||
        newHead.dy < 0 ||
        newHead.dy >= _gridSize) {
      _gameOver();
      return;
    }

    if (_snake.contains(newHead)) {
      _gameOver();
      return;
    }

    setState(() {
      _snake.insert(0, newHead);
      if (newHead == _food) {
        _score += 10;
        _spawnFood();
      } else {
        _snake.removeLast();
      }
    });
  }

  void _gameOver() {
    _timer?.cancel();
    setState(() {
      _isPlaying = false;
      _isGameOver = true;
      if (_score > _highScore) _highScore = _score;
    });
  }

  void _changeDirection(Direction newDirection) {
    const opposite = {
      Direction.up: Direction.down,
      Direction.down: Direction.up,
      Direction.left: Direction.right,
      Direction.right: Direction.left,
    };
    if (newDirection != opposite[_direction]) {
      _direction = newDirection;
    }
  }

  void _onPanStart(DragStartDetails details) {
    _swipeStart = details.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_swipeStart == null) return;
    final delta = details.localPosition - _swipeStart!;
    if (delta.distance < 20) return;

    if (delta.dx.abs() > delta.dy.abs()) {
      _changeDirection(delta.dx > 0 ? Direction.right : Direction.left);
    } else {
      _changeDirection(delta.dy > 0 ? Direction.down : Direction.up);
    }
    _swipeStart = details.localPosition;
  }

  void _onPanEnd(DragEndDetails details) {
    _swipeStart = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[850],
        title: const Text(
          'Snake Game',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Score: $_score',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    size: Size(
                      MediaQuery.of(context).size.width - 40,
                      MediaQuery.of(context).size.width - 40,
                    ),
                    painter: _GamePainter(
                      snake: _snake,
                      food: _food,
                      gridSize: _gridSize,
                      isGameOver: _isGameOver,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_isPlaying && !_isGameOver)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    _resetGame();
                    _startGame();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'START GAME',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          if (_isGameOver)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'GAME OVER',
                    style: TextStyle(
                      color: Colors.red[400],
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Score: $_score  |  Best: $_highScore',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        _resetGame();
                        _startGame();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'PLAY AGAIN',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_isPlaying)
            const Padding(
              padding: EdgeInsets.only(bottom: 32),
              child: Text(
                'Swipe on the grid to steer',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

enum Direction { up, down, left, right }

class _GamePainter extends CustomPainter {
  final List<Offset> snake;
  final Offset food;
  final int gridSize;
  final bool isGameOver;

  _GamePainter({
    required this.snake,
    required this.food,
    required this.gridSize,
    required this.isGameOver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / gridSize;

    final gridPaint = Paint()
      ..color = Colors.grey[800]!
      ..strokeWidth = 0.5;
    for (int i = 0; i <= gridSize; i++) {
      canvas.drawLine(
        Offset(i * cellSize, 0),
        Offset(i * cellSize, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, i * cellSize),
        Offset(size.width, i * cellSize),
        gridPaint,
      );
    }

    final foodPaint = Paint()..color = Colors.red;
    final foodCenter = Offset(
      food.dx * cellSize + cellSize / 2,
      food.dy * cellSize + cellSize / 2,
    );
    canvas.drawCircle(foodCenter, cellSize / 2.5, foodPaint);

    for (int i = 0; i < snake.length; i++) {
      final segment = snake[i];
      final paint = Paint()
        ..color = i == 0
            ? (isGameOver ? Colors.red : Colors.green)
            : Colors.green.withValues(alpha: 1.0 - (i * 0.03).clamp(0.0, 0.6));

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          segment.dx * cellSize + 1,
          segment.dy * cellSize + 1,
          cellSize - 2,
          cellSize - 2,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);

      if (i == 0) {
        final eyePaint = Paint()..color = Colors.white;
        final eyeSize = cellSize / 6;
        canvas.drawCircle(
          Offset(
            segment.dx * cellSize + cellSize * 0.35,
            segment.dy * cellSize + cellSize * 0.35,
          ),
          eyeSize,
          eyePaint,
        );
        canvas.drawCircle(
          Offset(
            segment.dx * cellSize + cellSize * 0.65,
            segment.dy * cellSize + cellSize * 0.35,
          ),
          eyeSize,
          eyePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
